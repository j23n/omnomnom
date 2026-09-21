import Foundation

/// Failures from the SQLite C API, carrying `sqlite3_errmsg` where available.
nonisolated enum SQLiteError: Error, Equatable, Sendable, LocalizedError {
    case open(String)
    case prepare(String)
    case bind(String)
    case step(String)

    var message: String {
        switch self {
        case .open(let m), .prepare(let m), .bind(let m), .step(let m): m
        }
    }

    var errorDescription: String? { message }
}
