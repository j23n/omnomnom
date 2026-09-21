import os

/// One `Logger` per subsystem area. Subsystem is the bundle identifier.
nonisolated enum AppLog {
    static let subsystem = "com.johanneswindelen.omnomnom"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let barcode = Logger(subsystem: subsystem, category: "barcode")
    static let foodDB = Logger(subsystem: subsystem, category: "fooddb")
    static let health = Logger(subsystem: subsystem, category: "health")
    static let store = Logger(subsystem: subsystem, category: "store")
}
