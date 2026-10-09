import Foundation
import SwiftData
import SwiftUI

/// The field, and everything the last line it sent has to say.
///
/// Over the tab bar rather than inside a screen, which is the structural decision of this
/// design: the field is on every tab because logging a meal is not a place you go. It was
/// Today's alone, and Today is where you look at what you ate — a different activity from
/// saying what you ate, and the one that was in the way of it.
///
/// Two things stack above the field: a sentence about something that went wrong, and what
/// was last logged with the way back from it. Each is absent unless it has something to say.
///
/// It does the work too, because the environment it needs is here: the resolver, the
/// logger, and the day the line goes into. Sending resolves the line and puts the sign-off
/// screen up; nothing is ever logged from the field itself.
struct ComposerBar: View {
    @Environment(\.composer) private var composer
    @Environment(\.modelContext) private var context
    @Environment(\.foodRepository) private var repository
    @Environment(\.health) private var health
    @Environment(\.appRouter) private var router
    /// Whether a model may read a line at all. Off means a line that has never been
    /// logged resolves to nothing, and the field says so.
    @AppStorage(EstimationModule.enabledKey) private var estimationEnabled = false
    /// The opt-in that already governs searching Open Food Facts by name, read here because
    /// it decides whether the product search is offered to the model as a tool.
    @AppStorage(BarcodeModule.productSearchKey) private var productSearchEnabled = false

    var body: some View {
        // The one thing on this screen that needs a binding is the sign-off sheet's item,
        // and the field's state comes out of the environment as a reference.
        @Bindable var composer = composer
        return VStack(spacing: 8) {
            if let banner = composer.banner {
                BannerView(message: banner) { composer.dismissBanner() }
            }
            if let logged = composer.lastLogged {
                LoggedLineBar(logged: logged, onUndo: undo) { composer.dismissLogged() }
            }
            ComposerView(model: composer, onSubmit: send)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .readableColumn()
        .animation(.default, value: composer.banner)
        .animation(.default, value: composer.lastLogged)
        // Presented with a stack of its own rather than pushed onto this one. The field
        // is on all four tabs and the sign-off screen has to come up over any of them;
        // what pushing was for — putting the food search screen up from inside it — a
        // sheet does too, as long as the sheet is the topmost thing, which it is.
        .sheet(item: $composer.resolution) { rows in
            NavigationStack {
                ResolutionScreen(
                    resolution: rows,
                    day: composer.day,
                    onChange: { composer.update($0) },
                    onRemove: { composer.remove($0) },
                    onAdd: { composer.add($0) },
                    onLog: { slot, at in
                        // The screen's own rows, not the ones it opened with: a food named
                        // in it has to be the one logged.
                        let edited = composer.resolution ?? rows
                        Task { await log(edited, mealSlot: slot, at: at) }
                    }
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        // Leaving logs nothing and keeps the line in the field, so the way
                        // out of this screen is never the way to lose a sentence.
                        Button("Cancel") { composer.dismissSheet() }
                    }
                }
            }
        }
        .onChange(of: router.pendingLine) { _, line in
            // Siri took a line it could not finish. The field picks it up so the user
            // lands on what became of it rather than on an empty field.
            guard let line else { return }
            composer.line = line
            router.clearPendingLine()
            send()
        }
    }

    /// Sends what is in the field: resolves it, and shows what came back.
    ///
    /// It does not log. What a model made of a sentence is a reading — the foods, the
    /// weights and the meal are all its guesses — and the sign-off screen is where those
    /// are read and corrected before anything reaches Health.
    private func send() {
        composer.submit(using: resolver)
    }

    /// Logs the rows the user signed off, into the meal and at the time that screen showed.
    private func log(_ resolution: LineResolution, mealSlot: MealSlot, at timestamp: Date) async {
        let logger = EntryLogger(context: context, health: health)
        let outcome = await logger.logLine(resolution, mealSlot: mealSlot, at: timestamp)
        // The field and the screen go together: what was typed has become rows in a day.
        composer.clear()
        composer.show(logged: LoggedLine(resolution: resolution, outcome: outcome))
    }

    /// Takes back what the last line wrote.
    private func undo() {
        guard let logged = composer.lastLogged else { return }
        composer.dismissLogged()
        Task {
            let logger = EntryLogger(context: context, health: health)
            let outcome = await logger.undo(logged)
            composer.banner = outcome.message
        }
    }

    /// The resolver, wired to this app's two opt-ins.
    private var resolver: LineResolver {
        LineResolver.app(
            context: context,
            repository: repository,
            estimationEnabled: estimationEnabled,
            productSearchEnabled: productSearchEnabled
        )
    }
}

#if DEBUG
#Preview("Empty") {
    ComposerBar()
        .previewEnvironment(seed: .typicalDay)
}

#Preview("Mid sentence") {
    let composer = ComposerModel()
    composer.line = "oats, banana, large coffee"
    return ComposerBar()
        .environment(\.composer, composer)
        .previewEnvironment(seed: .typicalDay)
}

#Preview("A line just logged") {
    let composer = ComposerModel()
    composer.show(logged: LoggedLine(
        line: "oats, banana, coffee", entryIDs: [UUID(), UUID(), UUID()], marked: 1, failed: 0
    ))
    return ComposerBar()
        .environment(\.composer, composer)
        .previewEnvironment(seed: .typicalDay)
}

#Preview("Something went wrong, over something logged") {
    let composer = ComposerModel()
    composer.banner = "No model is set up to read that. Choose one in Settings, or add food by searching."
    composer.show(logged: LoggedLine(line: "oats", entryIDs: [UUID()], marked: 0, failed: 0))
    return ComposerBar()
        .environment(\.composer, composer)
        .previewEnvironment(seed: .typicalDay)
}

#Preview("Accessibility 5") {
    let composer = ComposerModel()
    composer.show(logged: LoggedLine(line: "oats", entryIDs: [UUID()], marked: 1, failed: 0))
    return ComposerBar()
        .environment(\.composer, composer)
        .previewEnvironment(seed: .typicalDay)
        .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
