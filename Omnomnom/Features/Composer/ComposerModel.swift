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
    /// The sheet's content, non-nil while the sheet is up.
    var resolution: LineResolution?
    /// True while a line is being resolved, which is the only slow step on this path.
    var isResolving = false
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
        !isResolving && (!line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || image != nil)
    }

    /// Resolves what is in the field and opens the sheet on the answer.
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
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.isResolving = false
            if resolved.isEmpty {
                self.banner = Self.nothingFound(hasEstimator: resolver.estimator != nil)
                return
            }
            self.resolution = resolved
        }
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

    /// Clears the field after a line has been logged.
    func clear() {
        task?.cancel()
        task = nil
        line = ""
        image = nil
        resolution = nil
        isResolving = false
    }

    func dismissSheet() {
        resolution = nil
    }

    func dismissBanner() {
        banner = nil
    }

    /// Replaces one row, which is what correcting a food or an amount does.
    func update(_ row: ResolvedRow) {
        guard var resolution, let index = resolution.rows.firstIndex(where: { $0.id == row.id }) else { return }
        resolution.rows[index] = row
        self.resolution = resolution
    }

    /// Removes a row the user does not want, which is one of the two ways past a row
    /// that blocks.
    func remove(_ row: ResolvedRow) {
        guard var resolution else { return }
        resolution.rows.removeAll { $0.id == row.id }
        self.resolution = resolution.rows.isEmpty ? nil : resolution
    }
}
