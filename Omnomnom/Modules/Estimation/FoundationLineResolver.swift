import Foundation
import FoundationModels
import os

/// Apple's on-device model, reading a line by searching this device for itself.
///
/// The third conformer to `LineDriving`, and the one that costs nothing and sends nothing
/// anywhere. It exists because the claim that it could not be written was simply wrong:
/// `FoundationModels` has had tool calling since iOS 26 — a type conforming to `Tool` with
/// a name, a description, `@Generable` arguments and an async `call`, handed to
/// `LanguageModelSession(tools:)` — so the only thing standing between the on-device model
/// and a typed line was this file.
///
/// **The framework owns the loop, which is the one real difference from the other two.**
/// The HTTP drivers write the conversation out by hand: send, read the tool calls, run the
/// searches, send the results back, count the rounds. Here the session does all of that
/// inside one `respond` call — it invokes the tool, puts the output into its own transcript
/// and carries on — so the hard part of the other two files does not exist here at all.
///
/// What that costs is a bound, and this is a gap rather than a trade. The remote paths stop
/// at `LinePrompt.maximumRounds` round trips of a timed-out request each; this one stops
/// when the framework decides to, and the composer imposes no deadline of its own, so a
/// model that keeps searching keeps the sign-off screen waiting until the person cancels.
/// Nor is there an equivalent of "the model kept searching without answering", because this
/// driver never gets to decide it has had enough. Putting a deadline here means racing
/// `respond` against a sleep and cancelling the loser, which is worth doing once somebody
/// has measured what a real line actually takes on a real device — guessing the number
/// first would only move the gap. `docs/OPEN-QUESTIONS.md` holds it.
///
/// **Greedy sampling, so this is the one path that is actually deterministic.** The remote
/// drivers both gave up `temperature: 0` — current reasoning models reject it — so the same
/// line can resolve two ways there on consecutive days. Here `samplingMode: .greedy` is
/// accepted, as it already is for the Add screen's estimate, so a line that is resolved
/// twice resolves the same way twice without leaning on phrase memory to hide it.
///
/// **Main-actor for the reason the other two give**: the searches end at the shared
/// `ModelContext`, since the product one writes a cache row, so the thing holding them has
/// to be where that context is.
@MainActor
final class FoundationLineResolver: LineDriving {
    private let searcher: any LineSearching

    /// Nothing is injected but the searches. There is no address, no key and no model name
    /// to read, which is the whole of this provider's configuration: it is either available
    /// on the device or it is not, and `Estimators.driver` asks `EstimationAvailability`
    /// before building one of these.
    init(searcher: any LineSearching) {
        self.searcher = searcher
    }

    func resolve(_ input: EstimationInput) async throws -> DrivenLine {
        let run = LineSearchRun(searcher: searcher)
        var tools: [any Tool] = [FoodSearchTool(run: run)]
        // Declared only behind the opt-in, for the reason the other two paths give: an
        // undeclared tool cannot be called, so the model never spends a turn discovering
        // that a search it was offered answers nothing.
        if searcher.searchesProducts {
            tools.append(ProductSearchTool(run: run))
        }
        // The shape Apple's own tool-calling example uses: tools, then the instructions as a
        // string. One thing a first build may disagree with, and it would disagree with
        // `FoundationMealEstimator` in the same breath: the newer framework is reported to
        // want the model passed in rather than defaulted, which would add `model:` to both
        // call sites and nothing else.
        let session = LanguageModelSession(tools: tools, instructions: LinePrompt.instructions)
        let options = GenerationOptions(samplingMode: .greedy)
        do {
            let generated: GeneratedLine
            switch input {
            case .text(let line):
                let response = try await session.respond(
                    to: LinePrompt.text(line: line), generating: GeneratedLine.self, options: options
                )
                generated = response.content
            case .photo(let data, let line):
                guard #available(iOS 27, *) else { throw EstimationError.photoUnavailable }
                generated = try await PhotoPrompt.respond(
                    session: session, imageData: data, text: LinePrompt.photo(line: line),
                    generating: GeneratedLine.self, options: options
                )
            }
            try Task.checkCancellation()
            let pool = run.pool
            AppLog.estimation.info(
                "resolved a line on device: \(generated.items.count) items from \(pool.count) candidates"
            )
            return DrivenLine(answer: generated.resolved, pool: pool)
        } catch {
            let mapped = EstimationError.map(error)
            if mapped != .cancelled {
                AppLog.estimation.error("on-device line failed: \(error.localizedDescription, privacy: .public)")
            }
            throw mapped
        }
    }
}

/// One request's searches, and the candidates they have numbered so far.
///
/// A reference type because `Tool` is `Sendable` and a tool is handed to the session once,
/// at construction, while the pool it fills has to be readable afterwards by the resolver
/// that built it. A `@MainActor` class is the simplest thing that is both: its state is
/// protected by the actor, so it satisfies `Sendable` without the tools having to carry a
/// lock, and it is already where the searches need to run.
///
/// It is also the whole of the can't-invent-a-food invariant on this path. The ids the model
/// may name are the ids this object issued, so an answer naming anything else reads as "none
/// of these" exactly as 0 does — the same guarantee the other two drivers get from the same
/// `LineCandidatePool`, reached a different way.
@MainActor
final class LineSearchRun {
    private(set) var pool = LineCandidatePool()
    private let searcher: any LineSearching

    init(searcher: any LineSearching) {
        self.searcher = searcher
    }

    /// The bundled tables, numbered and worded as the model reads them.
    func foods(matching term: String) async -> String {
        LinePrompt.results(pool.add(foods: await searcher.foods(matching: term)))
    }

    /// Open Food Facts, the same way. Guarded a second time rather than trusted: the tool is
    /// only declared behind the opt-in, and this is what makes the opt-in true even if a
    /// future caller forgets that.
    func products(matching term: String) async -> String {
        guard searcher.searchesProducts else { return LinePrompt.noSuchSearch }
        return LinePrompt.results(pool.add(products: await searcher.products(matching: term)))
    }
}

/// What either search is asked for: a term, in the model's own choice of wording.
///
/// One arguments type for both tools, because both take exactly a term and two copies would
/// be two descriptions of the same field to keep in step.
@Generable(description: "A food to look for, in whatever wording is worth trying")
nonisolated struct LineSearchTerm: Sendable {
    @Guide(description: "The food to search for, in a few words. Try a different wording rather than guessing when a search finds nothing.")
    var term: String
}

/// The bundled tables as a tool the model may call.
///
/// The name and the description are `LinePrompt`'s, so this path offers the model the same
/// two searches under the same names and the same words as the other two. That is what makes
/// "a line reads the same whichever provider answered" a property of the app rather than a
/// hope.
nonisolated struct FoodSearchTool: Tool {
    typealias Arguments = LineSearchTerm

    let name = LinePrompt.foodTool
    let description = LinePrompt.foodToolDescription
    let run: LineSearchRun

    func call(arguments: LineSearchTerm) async throws -> String {
        await run.foods(matching: arguments.term)
    }
}

/// Open Food Facts as a tool, declared only when its opt-in is on.
nonisolated struct ProductSearchTool: Tool {
    typealias Arguments = LineSearchTerm

    let name = LinePrompt.productTool
    let description = LinePrompt.productToolDescription
    let run: LineSearchRun

    func call(arguments: LineSearchTerm) async throws -> String {
        await run.products(matching: arguments.term)
    }
}

/// The answer, in the shape guided generation can produce.
///
/// A mirror of `ResolvedLine` rather than `ResolvedLine` itself, for the reason
/// `EstimatedMeal` gives for not being `MealSlot`: the app's own type should not be a thing
/// a model is asked to produce. It also keeps this whole provider to one file — no other
/// path gains an import or a macro for it — so if a 3-billion-parameter model turns out to
/// choose badly among candidate rows, what is deleted is this file and one switch case.
///
/// The fields say the same things `LinePrompt.instructions` says in words and the remote
/// schemas say in JSON. Here they are said a third way because guided generation is a third
/// mechanism, not because anyone chose to describe the shape three times.
@Generable(description: "The foods one line of a food log names, each chosen from the search results by id")
nonisolated struct GeneratedLine: Sendable {
    @Guide(description: "Each distinct food or drink the line names", .maximumCount(12))
    var items: [GeneratedLineItem]

    @Guide(description: "Which meal these foods belong to, judged from the foods themselves and not from the time of day")
    var meal: EstimatedMeal

    @Guide(description: "One short sentence on what was assumed, and whether the choice is uncertain")
    var note: String

    /// Spelled out rather than left to the memberwise one, so the mapping below can be
    /// tested without a device: everything else in this file needs Apple Intelligence to
    /// run, and this part does not.
    init(items: [GeneratedLineItem], meal: EstimatedMeal = .snack, note: String = "") {
        self.items = items
        self.meal = meal
        self.note = note
    }

    /// The same answer in the app's own shape, which every driver hands back.
    var resolved: ResolvedLine {
        ResolvedLine(items: items.map(\.resolved), meal: meal, note: note)
    }
}

/// One food of an answered line, as guided generation produces it.
@Generable(description: "One food and which search result it is")
nonisolated struct GeneratedLineItem: Sendable {
    @Guide(description: "Short plain name of the food, as the person who ate it would say it")
    var name: String

    @Guide(description: "The id of the chosen search result. Answer 0 when no result is the food that was eaten: that is a correct answer and the person is asked.")
    var candidate: Int

    @Guide(description: "Weight of the portion eaten, in grams — not the package and not the whole dish", .range(1...3000))
    var grams: Double

    @Guide(description: "How sure this choice is")
    var certainty: GeneratedCertainty

    @Guide(description: "Set only when the weight and the chosen food do not go together, such as 200 g of a powder")
    var implausible: Bool

    init(
        name: String, candidate: Int, grams: Double,
        certainty: GeneratedCertainty = .certain, implausible: Bool = false
    ) {
        self.name = name
        self.candidate = candidate
        self.grams = grams
        self.certainty = certainty
        self.implausible = implausible
    }

    var resolved: ResolvedLineItem {
        ResolvedLineItem(
            name: name, candidate: candidate, grams: grams,
            certainty: certainty.certainty, implausible: implausible
        )
    }
}

/// How sure the model is, in the shape guided generation can produce.
///
/// The mirror of `VerdictCertainty` for the same reason as the rest of this shape. Mapped
/// across once here, so what "probable" is worth on a row goes on being decided in one
/// place for all three providers.
@Generable(description: "How sure a choice is")
nonisolated enum GeneratedCertainty: String, Hashable, Sendable {
    case certain
    case probable
    case unsure

    var certainty: VerdictCertainty {
        switch self {
        case .certain: .certain
        case .probable: .probable
        case .unsure: .unsure
        }
    }
}
