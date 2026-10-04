import AppIntents
import Foundation
import SwiftData

/// Logging a meal from a spoken or typed sentence, without opening the app.
///
/// The shortest path there is: say a line, and what resolves is in Health. It runs the
/// same four rungs the composer does, so a line logged before comes straight back from
/// memory and a new one is matched in the bundled tables.
///
/// It never opens the app to finish something, and it never logs a row it is unsure of.
/// What settles is logged; anything else is left on `AppRouter` so the composer has the
/// line ready the next time the app is opened, and the dialog says which rows are
/// waiting. Those are the only two outcomes, which is what keeps it safe to run from a
/// lock screen: this intent cannot put a figure into Health that nobody stood behind.
struct LogLineIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a meal"
    static let description = IntentDescription(
        "Logs what you ate from a sentence, such as oats, banana and coffee."
    )
    /// Stays in the background: the whole point is not having to open anything.
    static let openAppWhenRun = false

    @Parameter(title: "What you ate", requestValueDialog: "What did you eat?")
    var line: String

    @Dependency private var repository: FoodRepository
    @Dependency private var router: AppRouter
    @Dependency private var container: ModelContainer

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ModelContext(container)
        // No validator here on purpose. The model tier belongs behind its opt-in and
        // behind a screen that can show what it decided; an intent that silently asked a
        // model and logged the answer would be the one place nobody could see it work.
        // The same model the composer uses. Without one a spoken line resolves to nothing
        // and the dialog says so, rather than Siri reporting success over an empty log.
        let resolver = LineResolver(
            context: context, repository: repository, estimator: Estimators.current()
        )
        let resolution = await resolver.resolve(line)

        guard !resolution.isEmpty else {
            return .result(dialog: "I couldn't find a food in that.")
        }

        let settled = resolution.rows.filter(\.isSettled)
        guard !settled.isEmpty else {
            router.compose(line)
            return .result(dialog: "I wasn't sure about that one. It's ready in Omnomnom.")
        }

        let logger = EntryLogger(context: context, health: HealthStore())
        let timestamp = Date.now
        let outcome = await logger.logLine(
            LineResolution(line: line, rows: settled, wasChecked: resolution.wasChecked),
            mealSlot: MealSlot.inferred(from: timestamp),
            at: timestamp,
            origin: .dictated
        )
        let waiting = resolution.rows.count - settled.count
        if waiting > 0 { router.compose(line) }
        return .result(dialog: IntentDialog(stringLiteral: Self.dialog(logged: outcome.loggedCount, waiting: waiting)))
    }

    /// What Siri says back. Names what is waiting rather than how many failed, because
    /// nothing failed: those rows are a question the app will ask.
    static func dialog(logged: Int, waiting: Int) -> String {
        let first = logged == 1 ? "Logged one thing." : "Logged \(logged) things."
        guard waiting > 0 else { return first }
        let rest = waiting == 1
            ? "One more is waiting in Omnomnom."
            : "\(waiting) more are waiting in Omnomnom."
        return "\(first) \(rest)"
    }
}

/// The app's intents, so Siri and Shortcuts can find them.
///
/// `nonisolated`, unlike the intents themselves: the protocol's requirement is
/// nonisolated and a main-actor static property cannot satisfy it. Safe here because
/// there is no stored property to isolate — which is exactly why the intents, whose
/// `@Parameter` and `@Dependency` wrappers *are* mutable stored properties, must not be.
nonisolated struct OmnomnomShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // No phrase speaks the line itself. A shortcut phrase can only interpolate a
        // parameter whose type is an `AppEntity` or an `AppEnum`, and this one is free
        // text — the whole point is saying a sentence nobody enumerated. So the phrase
        // starts the intent and `requestValueDialog` on `line` asks for the sentence,
        // which costs one turn of dialogue and keeps the input open.
        AppShortcut(
            intent: LogLineIntent(),
            phrases: [
                "Log a meal in \(.applicationName)",
                "Log food in \(.applicationName)",
                "Log what I ate in \(.applicationName)",
            ],
            shortTitle: "Log a meal",
            systemImageName: "fork.knife"
        )
    }
}
