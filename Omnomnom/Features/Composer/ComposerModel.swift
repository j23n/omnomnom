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
    /// What the line resolved to, non-nil while the sign-off screen is up.
    var resolution: LineResolution?
    /// True while a line is being resolved, which is the slowest step on this path.
    var isResolving = false
    /// True while what came back is being written.
    var isLogging = false
    /// One sentence when something went wrong that the user can do nothing about.
    var banner: String?
    /// What was last logged, while the way back from it is still offered.
    ///
    /// On no timer, because two paths write in one tap and nothing else — a widget tap and
    /// accepting a usual meal — so for those this is the only way back. It goes on the next
    /// send, on a change of day, or when it is dismissed.
    var lastLogged: LoggedLine?
    /// The day a line goes into.
    ///
    /// The field is on every tab, and only one of them has a day in it. So the day is held
    /// here: Today sets it to whatever is on screen, and every other tab sets it back to
    /// today, which is the only day they could mean.
    var day: Date = Calendar.current.startOfDay(for: .now)

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

    /// Resolves what is in the field and opens the sign-off screen on the answer.
    ///
    /// **Nothing is ever logged straight from the field.** What a model made of a sentence
    /// is a reading, not a record: it picks the foods, it estimates the weights, and it
    /// decides which meal this was. Every one of those is shown, and changeable, before
    /// anything reaches Health. A line that resolved from memory has nothing left to decide
    /// and still shows what it is about to write.
    ///
    /// The field keeps what was typed until the screen logs it, so backing out of the
    /// screen leaves the line where it was rather than making someone type it again.
    func submit(using resolver: LineResolver) {
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
                banner = Self.nothingFound(canRead: resolver.canReadALine)
                return
            }
            resolution = resolved
        }
    }

    /// Points the field at a day, and drops an offer that was about another one.
    ///
    /// An Undo names entries on the day it was shown against. Carried to another day it
    /// would be a button over rows it has nothing to do with.
    func looking(at day: Date, calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: day)
        guard start != self.day else { return }
        self.day = start
        lastLogged = nil
    }

    /// Takes what a line wrote, and offers the way back from it.
    func show(logged: LoggedLine) {
        banner = nil
        lastLogged = logged
    }

    func dismissLogged() {
        lastLogged = nil
    }

    /// Why nothing came back.
    ///
    /// Two situations the user cannot tell apart from an empty sheet, and only one of them
    /// is about what they wrote. Saying "nothing looked like a food" to someone whose phone
    /// will never answer sends them back to rewrite a line that was fine.
    static func nothingFound(canRead: Bool) -> String {
        canRead
            ? "Nothing in that looked like a food."
            : "No model is set up to read that. Choose one in Settings, or add food by searching."
    }

    /// Clears the field and the screen over it: what a logged line, or an abandoned one,
    /// leaves behind.
    func clear() {
        task?.cancel()
        task = nil
        line = ""
        image = nil
        resolution = nil
        isResolving = false
        isLogging = false
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
        self.resolution = resolution
    }

    /// Appends a row for a food the user picked themselves, which is how something the
    /// line never said — or something the model missed — gets into the same meal rather
    /// than into a second one.
    func add(_ row: ResolvedRow) {
        guard var resolution else { return }
        resolution.append(row)
        self.resolution = resolution
    }

    /// Removes a row the user does not want, which is one of the two ways past a row that
    /// blocks the log.
    func remove(_ row: ResolvedRow) {
        guard var resolution else { return }
        resolution.remove(row)
        self.resolution = resolution.rows.isEmpty ? nil : resolution
    }


}
