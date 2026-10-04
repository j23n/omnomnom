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

    /// What the line looks like it holds, parsed on every keystroke.
    ///
    /// Only the parser runs here: no search, no model, nothing that touches a disk or a
    /// network, so it is safe on a keystroke. It is what lets the field show that it
    /// understood three foods before anything is committed.
    var preview: [ParsedItem] {
        LineParser.parse(line)
    }

    /// Whether there is anything worth resolving.
    var canSubmit: Bool {
        !isResolving && !preview.isEmpty
    }

    /// Resolves what is in the field and opens the sheet on the answer.
    func submit(using resolver: LineResolver) {
        guard canSubmit else { return }
        let line = self.line
        task?.cancel()
        isResolving = true
        task = Task { [weak self] in
            let resolved = await resolver.resolve(line)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.isResolving = false
            if resolved.isEmpty {
                self.banner = "Nothing in that line looked like a food."
                return
            }
            self.resolution = resolved
        }
    }

    /// Clears the field after a line has been logged.
    func clear() {
        task?.cancel()
        task = nil
        line = ""
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
