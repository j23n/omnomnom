import SwiftUI

/// The two notes that close both Library editors, in that order: that what has already
/// been logged is left alone, when anything has been, and why a save did not go through,
/// when one did not.
///
/// A view rather than a modifier because these are `Section`s, and a `Form` takes its
/// sections from its content; nothing can push one in from the outside.
struct EditorNotes: View {
    /// The reassurance about logged entries, or `nil` when there are none to reassure
    /// about. The wording is the caller's because the editors count different things.
    let loggedNote: String?
    let saveError: String?

    var body: some View {
        if let loggedNote {
            Section {
                Text(loggedNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        if let saveError {
            Section {
                Text(saveError)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

extension View {
    /// The chrome both Library editors wear: an inline title, Cancel, and a Done that
    /// stays off until the draft holds together.
    ///
    /// Dismissal is not a parameter. The sheet to close is whichever one this view is in,
    /// which the environment already knows, and a caller that had to hand it over could
    /// hand over the wrong one.
    func editorToolbar(
        title: String, isValid: Bool, onSave: @escaping () -> Void
    ) -> some View {
        modifier(EditorToolbar(title: title, isValid: isValid, onSave: onSave))
    }
}

/// The implementation of `editorToolbar`, a `ViewModifier` rather than a plain function
/// so that it can hold the `@Environment` read of `dismiss` itself.
private struct EditorToolbar: ViewModifier {
    let title: String
    let isValid: Bool
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onSave() }
                        .disabled(!isValid)
                }
            }
    }
}
