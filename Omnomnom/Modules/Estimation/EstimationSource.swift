import Foundation

/// The Sources screen entry for estimates, which come from no database at all.
nonisolated enum EstimationSource {
    static let name = "On-device estimation"
    static let publisher = "Apple Intelligence, on this device"
    static let note = "Estimates come from Apple's on-device model, not from any database, and are only as good as the description or photo."
}
