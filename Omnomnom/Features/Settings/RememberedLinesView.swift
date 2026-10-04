import os
import SwiftData
import SwiftUI

/// Every line the app has remembered, and what each one resolved to.
///
/// Inspect-and-forget. Nothing here has to be tended: lines are recorded by logging them
/// and rewritten by correcting them, and this screen exists so that memory is not a black
/// box rather than so it can be curated. A line that is wrong is best fixed by logging it
/// again correctly, which is the same act that wrote it.
///
/// It is also where a line becomes a meal's usual, which is the only way a baseline is
/// ever created: from something the user has actually eaten repeatedly, never from a
/// questionnaire.
struct RememberedLinesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Phrase.lastUsed, order: .reverse) private var phrases: [Phrase]
    @Query private var baselines: [BaselinePhrase]

    var body: some View {
        List {
            if phrases.isEmpty {
                ContentUnavailableView(
                    "Nothing remembered yet",
                    systemImage: "text.line.first.and.arrowtriangle.forward",
                    description: Text("Lines you log are remembered here, so the second time is free.")
                )
            }
            // One row per line rather than a section each: a delete action belongs to a
            // ForEach of rows, and a ForEach of sections cannot carry one.
            Section {
                ForEach(phrases) { phrase in
                    DisclosureGroup {
                        ForEach(phrase.orderedItems) { item in
                            LabeledContent(item.food?.name ?? item.recipe?.name ?? item.name) {
                                Text(Formatters.fieldText(item.amount))
                                    .monospacedDigit()
                            }
                        }
                        if let slot = phrase.lastSlot {
                            if isBaseline(phrase, slot) {
                                Button("Stop proposing this for \(slot.displayName.lowercased())") {
                                    clearBaseline(slot)
                                }
                            } else {
                                Button("Propose this for \(slot.displayName.lowercased())") {
                                    setBaseline(phrase, slot)
                                }
                            }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(phrase.text)
                            Text(Self.summary(phrase))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: forget)
            } footer: {
                if !phrases.isEmpty {
                    Text("Lines are recorded by logging them and rewritten by correcting them. Forgetting one is harmless: it comes back the next time you log it.")
                }
            }
        }
        .navigationTitle("Remembered lines")
        .toolbar {
            if !phrases.isEmpty {
                EditButton()
            }
        }
    }

    private func isBaseline(_ phrase: Phrase, _ slot: MealSlot) -> Bool {
        baselines.contains { $0.mealSlot == slot && $0.phrase?.id == phrase.id }
    }

    /// "Logged 6 times, last on 3 Oct" — what is there, never a share of anything.
    static func summary(_ phrase: Phrase) -> String {
        let times = phrase.useCount == 1 ? "Logged once" : "Logged \(phrase.useCount) times"
        return "\(times), last on \(phrase.lastUsed.formatted(.dateTime.day().month(.abbreviated)))"
    }

    private func setBaseline(_ phrase: Phrase, _ slot: MealSlot) {
        save("propose a line") { try BaselinePhrase.set(phrase, for: slot, in: context) }
    }

    private func clearBaseline(_ slot: MealSlot) {
        save("stop proposing a line") { try BaselinePhrase.clear(for: slot, in: context) }
    }

    /// Forgetting a line is allowed and harmless: it is recorded again the next time it
    /// is logged.
    private func forget(_ offsets: IndexSet) {
        save("forget a line") {
            for index in offsets { context.delete(phrases[index]) }
        }
    }

    private func save(_ what: String, _ work: () throws -> Void) {
        do {
            try work()
            try context.save()
        } catch {
            AppLog.store.error("could not \(what, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

#if DEBUG
#Preview("Remembered lines") {
    NavigationStack {
        RememberedLinesView()
    }
    .previewEnvironment(seed: .typicalDay)
}

#Preview("Nothing yet") {
    NavigationStack {
        RememberedLinesView()
    }
    .previewEnvironment(seed: .empty)
}
#endif
