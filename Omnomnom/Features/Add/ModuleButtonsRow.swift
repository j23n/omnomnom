import DeveloperToolsSupport
import SwiftUI

/// Scan and Estimate as list content on the Add sheet: the navigation bar is hidden
/// while search is active, which is from the moment the sheet opens, so toolbar items
/// would never be seen. Each button shows only while its module is on; with neither
/// on, the row takes no space. The buttons sit side by side and stack at large type.
/// Tapping one flips its trigger; the entry-point modifier that owns the sheet reacts.
struct ModuleButtonsRow: View {
    @Binding var scanRequested: Bool
    @Binding var estimateRequested: Bool

    @AppStorage(BarcodeModule.enabledKey) private var scanningEnabled = false
    @AppStorage(EstimationModule.enabledKey) private var estimationEnabled = false

    var body: some View {
        if scanningEnabled || estimationEnabled {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { buttons }
                VStack(spacing: 12) { buttons }
            }
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
        }
    }

    @ViewBuilder
    private var buttons: some View {
        if scanningEnabled {
            Button {
                scanRequested = true
            } label: {
                Label("Scan", systemImage: "barcode.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        if estimationEnabled {
            Button {
                estimateRequested = true
            } label: {
                Label("Estimate", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
}

#if DEBUG
#Preview("Both modules") {
    List {
        ModuleButtonsRow(scanRequested: .constant(false), estimateRequested: .constant(false))
        Section("Recent") {
            Text("Oats")
        }
    }
    .listStyle(.plain)
    .defaultAppStorage(PreviewDefaults.modulesOn)
}

#Preview("Scan only") {
    List {
        ModuleButtonsRow(scanRequested: .constant(false), estimateRequested: .constant(false))
    }
    .listStyle(.plain)
    .defaultAppStorage(PreviewDefaults.make(barcode: true))
}

#Preview("Both modules, accessibility 5") {
    List {
        ModuleButtonsRow(scanRequested: .constant(false), estimateRequested: .constant(false))
    }
    .listStyle(.plain)
    .defaultAppStorage(PreviewDefaults.modulesOn)
    .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
