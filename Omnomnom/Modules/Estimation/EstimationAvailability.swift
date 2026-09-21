import Foundation
import FoundationModels

/// The Settings key shared by the toggle, the Add sheet and the sheet.
nonisolated enum EstimationModule {
    static let enabledKey = "mealEstimationEnabled"
}

/// Whether the on-device model can estimate right now, with one sentence for each
/// state. Checked in the order the plan asks for: the model first, then whether this OS
/// can take a photo, because a device on iOS 27 with Apple Intelligence off fails the
/// first check and that is what the user needs to hear.
nonisolated enum EstimationAvailability: Hashable, Sendable {
    /// The model answers; `photo` says whether an image can go with the prompt (iOS 27).
    case available(photo: Bool)
    /// The device has no Apple Intelligence support at all.
    case deviceNotEligible
    /// Supported device, but Apple Intelligence is switched off in Settings.
    case appleIntelligenceNotEnabled
    /// The model assets are still downloading or were removed.
    case modelNotReady
    /// A reason this build does not know; the text describes it.
    case unavailable(String)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    /// Whether a photo can be attached: available on iOS 27 or later.
    var supportsPhoto: Bool {
        if case .available(let photo) = self { return photo }
        return false
    }

    /// What to tell the user, one sentence, always present.
    var message: String {
        switch self {
        case .available(photo: true):
            "Ready. Describe a meal or add a photo of it."
        case .available(photo: false):
            "Ready. Describe a meal in words; photos need iOS 27."
        case .deviceNotEligible:
            "This device does not support Apple Intelligence, so meals cannot be estimated."
        case .appleIntelligenceNotEnabled:
            "Turn on Apple Intelligence in Settings to estimate meals."
        case .modelNotReady:
            "The on-device model is not ready yet; it downloads on its own. Try again later."
        case .unavailable(let reason):
            "Meal estimation is not available right now: \(reason)"
        }
    }

    /// Reads the model state. Main-actor so it is called where the UI decides.
    @MainActor
    static func current() -> EstimationAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            if #available(iOS 27, *) {
                return .available(photo: true)
            }
            return .available(photo: false)
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .deviceNotEligible
            case .appleIntelligenceNotEnabled:
                return .appleIntelligenceNotEnabled
            case .modelNotReady:
                return .modelNotReady
            @unknown default:
                return .unavailable(String(describing: reason))
            }
        }
    }
}
