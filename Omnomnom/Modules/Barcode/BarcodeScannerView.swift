import Foundation
import os
import SwiftUI
import UIKit
import Vision
import VisionKit

/// The camera view that reads one barcode. `DataScannerViewController` is the one UIKit
/// piece of the app; this wrapper starts it, hands the first payload that passes
/// `Barcode.normalize` to `onScan` in canonical form, then stops. Misreads that fail
/// the check digit are skipped so the camera keeps looking. Failures go to `onError`.
struct BarcodeScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onError: onError)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    /// Starts scanning once; SwiftUI calls this right after `makeUIViewController`.
    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.startIfNeeded(scanner)
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    /// Main-actor like the delegate protocol it adopts; VisionKit calls it on main.
    final class Coordinator: DataScannerViewControllerDelegate {
        private let onScan: (String) -> Void
        private let onError: (String) -> Void
        private var hasStarted = false
        private var hasScanned = false

        init(onScan: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
            self.onScan = onScan
            self.onError = onError
        }

        func startIfNeeded(_ scanner: DataScannerViewController) {
            guard !hasStarted else { return }
            hasStarted = true
            do {
                try scanner.startScanning()
            } catch {
                AppLog.barcode.error("scanner did not start: \(error.localizedDescription, privacy: .public)")
                onError("The camera could not start: \(error.localizedDescription)")
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !hasScanned else { return }
            for item in addedItems {
                guard case .barcode(let barcode) = item, let payload = barcode.payloadStringValue else { continue }
                let code = barcode.observation.symbology == .upce
                    ? (Barcode.expandUPCE(payload) ?? Barcode.normalize(payload))
                    : Barcode.normalize(payload)
                guard let code else { continue }
                hasScanned = true
                dataScanner.stopScanning()
                onScan(code)
                return
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            switch error {
            case .unsupported:
                onError("This device cannot scan barcodes. Type the digits instead.")
            case .cameraRestricted:
                onError("The camera is restricted or in use by another app.")
            @unknown default:
                onError("The scanner stopped: \(error.localizedDescription)")
            }
        }
    }
}
