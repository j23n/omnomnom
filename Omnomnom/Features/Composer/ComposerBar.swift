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
/// Four things stack above the field, newest nearest the thumb: a sentence about something
/// that went wrong, what the last send wrote with the way back from it, and the part of a
/// line nothing could be placed. Each is absent unless it has something to say.
///
/// It does the work too, because the environment it needs is here: the four rungs of the
/// resolver, the logger, and the day the line goes into.
struct ComposerBar: View {
    @Environment(\.composer) private var composer
    @Environment(\.modelContext) private var context
    @Environment(\.foodRepository) private var repository
    @Environment(\.health) private var health
    @Environment(\.appRouter) private var router
    /// The validator runs on the same model the estimate module uses, behind the same
    /// opt-in, so a user who has not turned that on is not quietly handed a model call.
    @AppStorage(EstimationModule.enabledKey) private var estimationEnabled = false
    /// The opt-in that already governs searching Open Food Facts by name, read here because
    /// the fourth rung is that same search asked by the resolver rather than by the user.
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
            if let note = composer.unplacedNote {
                UnplacedRowsBar(
                    note: note,
                    onPick: { composer.askAboutUnplaced() },
                    onLeave: { composer.clearUnplaced() }
                )
            }
            ComposerView(model: composer, onSubmit: send)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .readableColumn()
        .animation(.default, value: composer.banner)
        .animation(.default, value: composer.lastLogged)
        .animation(.default, value: composer.unplacedNote)
        // Presented, not pushed. It is reached from every tab now, and only three of them
        // have a navigation stack to push onto; a sheet is also what it has to be to put
        // the food search screen up over itself.
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
                        composer.clearUnplaced()
                        Task { await log(edited, mealSlot: slot, at: at) }
                    }
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        // Leaving does not log and does not drop the question: the bar
                        // over the field still has it.
                        Button("Not now") { composer.dismissSheet() }
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

    /// Sends what is in the field: resolves it, and logs what came back.
    ///
    /// The meal and the time are nobody's decision here. The model's reading of which meal
    /// this is wins, since oats at nine in the evening are breakfast, and the clock decides
    /// when nothing read it. Both are changeable afterwards, on the entry itself.
    private func send() {
        let day = composer.day
        composer.submit(using: resolver) { placed in
            let slot = placed.meal ?? MealSlot.inferred(from: QuantitySheet.defaultTimestamp(on: day))
            return await log(placed, mealSlot: slot, at: slot.timestamp(on: day))
        }
    }

    /// Logs every row and offers the way back from it.
    ///
    /// Nothing is signed off first. What the line said, with a food behind it and no
    /// question over it, is in the day by the time the user has looked up from the field,
    /// and `LoggedLine` is what makes that safe rather than merely fast.
    @discardableResult
    private func log(
        _ resolution: LineResolution, mealSlot: MealSlot, at timestamp: Date
    ) async -> LoggedLine {
        let logger = EntryLogger(context: context, health: health)
        let outcome = await logger.logLine(resolution, mealSlot: mealSlot, at: timestamp)
        let logged = LoggedLine(resolution: resolution, outcome: outcome)
        composer.show(logged: logged)
        return logged
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

    /// The four rungs, wired to this app's settings.
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

#Preview("Everything at once") {
    let composer = ComposerModel()
    composer.banner = "No model is set up to read that. Choose one in Settings, or add food by searching."
    composer.show(logged: LoggedLine(line: "oats", entryIDs: [UUID()], marked: 0, failed: 0))
    composer.unplaced = LineResolution(
        line: "oats and a flapjack",
        rows: [ResolvedRow(
            name: "flapjack", choice: nil, amount: 0, origin: .database, confidence: .unsure
        )],
        wasChecked: false
    )
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
