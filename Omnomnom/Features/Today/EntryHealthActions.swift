import Foundation
import SwiftUI

/// The two choices for an entry Health no longer holds in full: write it again, or drop
/// it here as well. Presented for `TodayViewModel.healthActionEntry`; clearing it closes
/// the dialog.
struct EntryHealthActions: ViewModifier {
    let model: TodayViewModel
    let onRestore: (LogEntry) -> Void
    let onRemove: (LogEntry) -> Void

    private var isPresented: Binding<Bool> {
        Binding(
            get: { model.healthActionEntry != nil },
            set: { if !$0 { model.healthActionEntry = nil } }
        )
    }

    func body(content: Content) -> some View {
        content.confirmationDialog(
            Text(model.healthActionEntry?.foodName ?? ""),
            isPresented: isPresented,
            titleVisibility: .visible,
            presenting: model.healthActionEntry
        ) { entry in
            Button("Restore to Health") { onRestore(entry) }
            Button("Remove here", role: .destructive) { onRemove(entry) }
        } message: { entry in
            Text(Self.message(for: entry))
        }
    }

    /// Names what Health dropped, then says what each choice does.
    static func message(for entry: LogEntry) -> String {
        let missing = entry.missingFromHealth
        let what: String
        if entry.healthState == .gone || missing.count == entry.written.count {
            what = "Health no longer has this entry."
        } else {
            what = "Health no longer has \(missing.map { $0.displayName.lowercased() }.formatted(.list(type: .and)))."
        }
        return "\(what) Restore writes it to Health again; Remove deletes it from this app only."
    }
}
