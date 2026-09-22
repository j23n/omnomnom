import Foundation
import SwiftData
import SwiftUI
import UIKit

/// Scans or types one barcode, resolves it, hands the outcome back and dismisses. The
/// camera appears only when the scanner can run; the field is always there, because a
/// worn label or a declined camera must not block logging.
struct BarcodeScanSheet: View {
    let onOutcome: (BarcodeLookupOutcome) -> Void
    /// A fixed scanner state for previews; `nil` reads the device and asks for the camera.
    private let fixedAvailability: BarcodeAvailability?

    init(availability: BarcodeAvailability? = nil, onOutcome: @escaping (BarcodeLookupOutcome) -> Void) {
        fixedAvailability = availability
        self.onOutcome = onOutcome
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var availability: BarcodeAvailability?
    @State private var manualCode = ""
    @State private var message: String?
    @State private var isResolving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if availability == .available {
                    BarcodeScannerView(onScan: { resolve($0) }, onError: { message = $0 })
                        .frame(maxWidth: .infinity)
                        .frame(height: 280)
                        .clipped()
                        .accessibilityLabel("Camera viewfinder. Point it at a barcode.")
                }
                Form {
                    if let text = message ?? availability?.message {
                        Section {
                            Text(text)
                            if availability == .cameraDenied, let url = URL(string: UIApplication.openSettingsURLString) {
                                Link("Open app settings", destination: url)
                            }
                        }
                    }
                    Section {
                        TextField("Digits under the bars", text: $manualCode)
                            .keyboardType(.numberPad)
                            .accessibilityLabel("Barcode digits")
                            .onSubmit { resolve(manualCode) }
                        Button("Look up") { resolve(manualCode) }
                            .disabled(manualCode.isEmpty || isResolving)
                    } header: {
                        Text("Enter barcode")
                    } footer: {
                        Text("8 digits (EAN-8), 12 (UPC-A) or 13 (EAN-13).")
                    }
                    if isResolving {
                        Section {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Looking up…")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Scan barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    /// Reads the availability, asking for the camera first if it was never asked.
    private func load() async {
        if let fixedAvailability {
            availability = fixedAvailability
            return
        }
        var state = BarcodeAvailability.current()
        if state == .cameraNotDetermined {
            state = await BarcodeAvailability.requestingCamera()
        }
        availability = state
    }

    /// Validates, resolves through the flow, reports and closes. An invalid code only
    /// shows a message; the scanner never emits one, so this catches typed mistakes.
    private func resolve(_ raw: String) {
        guard !isResolving else { return }
        guard let code = Barcode.normalize(raw) else {
            message = "That is not a valid barcode. Check the digits, including the last one."
            return
        }
        isResolving = true
        message = nil
        Task {
            let client = OpenFoodFactsClient(transport: URLSessionTransport(), userAgent: UserAgent.current())
            let outcome = await BarcodeLookupFlow(context: context, client: client).resolve(code: code)
            isResolving = false
            onOutcome(outcome)
            dismiss()
        }
    }
}

// `.available` is not previewed: it would put a `DataScannerViewController` on screen,
// which previews must never do. The four states without a camera are here.

#if DEBUG
#Preview("Unsupported device") {
    BarcodeScanSheet(availability: .unsupportedDevice) { _ in }
        .previewEnvironment(seed: .empty)
}

#Preview("Camera unavailable") {
    BarcodeScanSheet(availability: .unavailable) { _ in }
        .previewEnvironment(seed: .empty)
}

#Preview("Camera denied") {
    BarcodeScanSheet(availability: .cameraDenied) { _ in }
        .previewEnvironment(seed: .empty)
}

#Preview("Camera not determined") {
    BarcodeScanSheet(availability: .cameraNotDetermined) { _ in }
        .previewEnvironment(seed: .empty)
}

#Preview("Camera denied, accessibility 5") {
    BarcodeScanSheet(availability: .cameraDenied) { _ in }
        .previewEnvironment(seed: .empty)
        .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
