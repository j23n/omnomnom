import Foundation
import Observation
import os
import SwiftData

/// The composer's state: what has been typed, and what resolving it produced.
///
/// Resolving is one task at a time and the newest wins, because a user who edits the
/// line while the model is thinking about the last version of it should get an answer
/// about what they typed, not about what they had typed.
@Observable
final class ComposerModel {
    /// What is in the field.
    var line: String = ""
    /// The sign-off screen's content, non-nil while that screen is up.
    ///
    /// Only ever the rows a send could not place. A line that resolved cleanly is logged
    /// without this ever being set, which is what the field is for.
    var resolution: LineResolution?
    /// Rows the last send could not write, waiting for a word from the user.
    ///
    /// Held here and not stored, which is the one thing this loses: quit the app with a
    /// question outstanding and the words that raised it are gone. What they named was
    /// never logged, so nothing is wrong in the record — only unanswered.
    var unplaced: LineResolution?
    /// True while a line is being resolved, which is the slowest step on this path.
    var isResolving = false
    /// True while what came back is being written.
    var isLogging = false
    /// One sentence when something went wrong that the user can do nothing about.
    var banner: String?

    private var task: Task<Void, Never>?

    /// A photograph to send with the words, when one has been taken or picked.
    ///
    /// The camera used to be its own feature, putting this app's foods into the system's
    /// camera results. It is an attachment to the one input now: a picture answers the same
    /// question a sentence does, and the model takes either.
    var image: Data?

    /// Whether there is anything worth resolving.
    ///
    /// No parse happens while typing any more, so this cannot ask what the line holds —
    /// only whether there is anything in it. That is the whole cost of giving the question
    /// to a model: nothing is understood until it is asked.
    var canSubmit: Bool {
        !isBusy && (!line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || image != nil)
    }

    /// Whether the composer is in the middle of something, by either of the two steps.
    /// One flag for the field to read, so the spinner does not blink between them.
    var isBusy: Bool { isResolving || isLogging }

    /// Resolves what is in the field and logs it.
    ///
    /// Sending is the whole act. Nothing is held for a sign-off: what the line said with a
    /// food behind it goes into the day, and `write` is what leaves the offer to take that
    /// back behind it. The rows nothing could be placed on stay in `unplaced`, where
    /// they are one question and not a gate — four foods of five in the day beats none of
    /// them, which is the same rule `logLine` follows row by row.
    func submit(using resolver: LineResolver, writing write: @escaping (LineResolution) async -> Void) {
        guard canSubmit else { return }
        let line = self.line
        let input: EstimationInput = if let image {
            .photo(image, description: line.isEmpty ? nil : line)
        } else {
            .text(line)
        }
        task?.cancel()
        isResolving = true
        task = Task { [weak self] in
            let resolved = await resolver.resolve(input, line: line)
            guard !Task.isCancelled, let self else { return }
            isResolving = false
            if resolved.isEmpty {
                banner = Self.nothingFound(hasEstimator: resolver.estimator != nil)
                return
            }
            // The field empties here rather than after the write. What was typed is
            // understood by now, and leaving it standing invites the same line twice.
            clearField()
            unplaced = resolved.unplaced
            guard let placed = resolved.placed else { return }
            isLogging = true
            await write(placed)
            isLogging = false
        }
    }

    /// Opens the sign-off screen on the rows the send could not place, which is the only
    /// thing that screen is for now.
    func askAboutUnplaced() {
        guard let unplaced else { return }
        resolution = unplaced
    }

    /// Everything about a line has been dealt with: the question is answered or dropped.
    func clearUnplaced() {
        unplaced = nil
        resolution = nil
    }

    /// "1 food needs a word from you."
    var unplacedNote: String? {
        guard let unplaced else { return nil }
        return unplaced.rows.count == 1
            ? "1 food needs a word from you."
            : "\(unplaced.rows.count) foods need a word from you."
    }

    /// Why nothing came back.
    ///
    /// Two situations the user cannot tell apart from an empty sheet, and only one of them
    /// is about what they wrote. Saying "nothing looked like a food" to someone whose phone
    /// will never answer sends them back to rewrite a line that was fine.
    static func nothingFound(hasEstimator: Bool) -> String {
        hasEstimator
            ? "Nothing in that looked like a food."
            : "No model is set up to read that. Choose one in Settings, or add food by searching."
    }

    /// Clears the field and everything outstanding, which is what abandoning a line means.
    func clear() {
        task?.cancel()
        task = nil
        clearField()
        unplaced = nil
        resolution = nil
        isLogging = false
    }

    /// Empties what was typed, leaving any outstanding question alone.
    private func clearField() {
        line = ""
        image = nil
        isResolving = false
    }

    func dismissSheet() {
        resolution = nil
    }

    func dismissBanner() {
        banner = nil
    }

    /// Replaces one row, which is what naming a food or setting an amount does.
    func update(_ row: ResolvedRow) {
        guard var resolution else { return }
        resolution.replace(row)
        show(resolution)
    }

    /// Appends a row for a food the user picked themselves, which is how something the
    /// line never said — or something the model missed — gets into the same meal rather
    /// than into a second one.
    func add(_ row: ResolvedRow) {
        guard var resolution else { return }
        resolution.append(row)
        show(resolution)
    }

    /// Removes a row the user does not want, which is one of the two ways past a row
    /// nothing could be placed on.
    func remove(_ row: ResolvedRow) {
        guard var resolution else { return }
        resolution.remove(row)
        if resolution.rows.isEmpty {
            clearUnplaced()
        } else {
            show(resolution)
        }
    }

    /// Puts an edited set of rows back, in both the places that hold it.
    ///
    /// The screen and the bar are two views of one thing: the only rows that reach the
    /// screen are the ones the bar is asking about, so a food named there has to change
    /// what the bar says about what is left.
    private func show(_ resolution: LineResolution) {
        self.resolution = resolution
        unplaced = resolution
    }
}
