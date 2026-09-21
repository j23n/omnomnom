import Foundation
import SwiftUI

/// Which sheet the barcode entry point has up.
private nonisolated enum BarcodeStage: Identifiable, Sendable {
    case scan
    case manual(ProductPrefill)

    var id: String {
        switch self {
        case .scan: "scan"
        case .manual(let prefill): "manual-\(prefill.barcode)"
        }
    }
}

/// The Scan button on the Add sheet and the sheets behind it: the scanner, then either
/// the Quantity sheet through `onFound` or, after a miss, the food editor prefilled with
/// the barcode, whose saved food ends in `onFound` too. Shown only in log mode with the
/// module turned on. Each next sheet is presented from `onDismiss` of the previous one,
/// so two presentations never overlap.
struct BarcodeEntryPoint: ViewModifier {
    let isActive: Bool
    let onFound: (FoodChoice) -> Void

    @AppStorage(BarcodeModule.enabledKey) private var scanningEnabled = false
    @State private var stage: BarcodeStage?
    @State private var pending: BarcodeLookupOutcome?

    func body(content: Content) -> some View {
        content
            .toolbar {
                if isActive, scanningEnabled {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Scan", systemImage: "barcode.viewfinder") { stage = .scan }
                    }
                }
            }
            .sheet(item: $stage, onDismiss: { advance() }) { stage in
                switch stage {
                case .scan:
                    BarcodeScanSheet { pending = $0 }
                case .manual(let prefill):
                    CustomFoodEditorView(food: nil, product: prefill) { food in
                        pending = food.choice.map { BarcodeLookupOutcome.found($0) }
                    }
                }
            }
    }

    /// Runs once the sheet is gone: a found product opens the Quantity sheet, a miss
    /// opens the editor.
    private func advance() {
        guard let outcome = pending else { return }
        pending = nil
        switch outcome {
        case .found(let choice):
            onFound(choice)
        case .manual(let barcode, let prefillName, let reason):
            stage = .manual(ProductPrefill(barcode: barcode, name: prefillName, reason: reason))
        }
    }
}
