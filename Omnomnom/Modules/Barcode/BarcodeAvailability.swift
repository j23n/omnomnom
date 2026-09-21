import AVFoundation
import Foundation
import VisionKit

/// Whether the scanner can run right now, with one sentence for each reason it cannot.
/// Checked in order: the device, then camera permission, then whether VisionKit can
/// have the camera at all.
nonisolated enum BarcodeAvailability: Hashable, Sendable {
    case available
    /// No Neural Engine: `DataScannerViewController.isSupported` is false.
    case unsupportedDevice
    /// Camera access is granted but `isAvailable` is false: in use elsewhere or restricted.
    case unavailable
    /// The user declined camera access, or a restriction forbids it.
    case cameraDenied
    /// The system prompt has not been shown yet; `requestingCamera` shows it.
    case cameraNotDetermined

    /// What to tell the user; `nil` when the scanner can run.
    var message: String? {
        switch self {
        case .available: nil
        case .unsupportedDevice: "This device cannot scan barcodes. Type the digits instead."
        case .unavailable: "The camera is in use by another app or restricted right now."
        case .cameraDenied: "Camera access is not allowed. Turn it on in Settings to scan."
        case .cameraNotDetermined: "Allow camera access to scan barcodes."
        }
    }

    /// Reads the device and permission state. Main-actor because VisionKit's checks are.
    @MainActor
    static func current() -> BarcodeAvailability {
        guard DataScannerViewController.isSupported else { return .unsupportedDevice }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            return .cameraNotDetermined
        case .denied, .restricted:
            return .cameraDenied
        case .authorized:
            break
        @unknown default:
            return .cameraDenied
        }
        return DataScannerViewController.isAvailable ? .available : .unavailable
    }

    /// Shows the system camera prompt, then reads the state again.
    @MainActor
    static func requestingCamera() async -> BarcodeAvailability {
        _ = await AVCaptureDevice.requestAccess(for: .video)
        return current()
    }
}
