import Foundation
import SwiftUI

/// The Estimate button on the Add sheet and the sheet behind it. Shown only in log
/// mode (`day` set) with the module turned on. Tapping it checks the model first: when
/// it cannot answer, an alert says why instead of opening a sheet that could do nothing.
struct EstimationEntryPoint: ViewModifier {
    /// The day being logged into; `nil` hides the button.
    let day: Date?
    /// Receives the banner text once the estimate's entries are saved.
    let onLogged: (String) -> Void

    @AppStorage(EstimationModule.enabledKey) private var estimationEnabled = false
    @State private var isPresented = false
    @State private var unavailable: EstimationAvailability?

    private var showsUnavailable: Binding<Bool> {
        Binding(
            get: { unavailable != nil },
            set: { if !$0 { unavailable = nil } }
        )
    }

    func body(content: Content) -> some View {
        content
            .toolbar {
                if day != nil, estimationEnabled {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Estimate", systemImage: "sparkles") { open() }
                    }
                }
            }
            .sheet(isPresented: $isPresented) {
                if let day {
                    EstimationSheet(day: day) { message in
                        isPresented = false
                        onLogged(message)
                    }
                }
            }
            .alert("Meal estimation unavailable", isPresented: showsUnavailable) {
                Button("OK") { unavailable = nil }
            } message: {
                Text(unavailable?.message ?? "")
            }
    }

    /// The model is checked at the moment of the tap, since Apple Intelligence can be
    /// switched off, or finish downloading, while the app is open.
    private func open() {
        let availability = EstimationAvailability.current()
        if availability.isAvailable {
            isPresented = true
        } else {
            unavailable = availability
        }
    }
}
