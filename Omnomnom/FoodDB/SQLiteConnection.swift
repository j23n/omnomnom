import Foundation
import SQLite3

/// Owns one read-only `sqlite3` handle and its prepared statements.
///
/// Not thread-safe and not `Sendable`: it lives inside `SQLiteDatabase` and never
/// leaves it. Finalizes statements and closes the handle when deallocated, which is
/// how the actor's `deinit` releases the C resources without touching actor state.
nonisolated final class SQLiteConnection {
    private var handle: OpaquePointer?
    private var statements: [String: OpaquePointer] = [:]

    /// `SQLITE_TRANSIENT` is a macro the importer cannot express; this is its value.
    static let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Opens `url` read-only through a `file:` URI with `immutable=1`, so no journal
    /// or lock files are created next to a bundle resource.
    init(url: URL) throws {
        let uri = url.absoluteString + "?immutable=1"
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX
        var opened: OpaquePointer?
        let result = sqlite3_open_v2(uri, &opened, flags, nil)
        guard result == SQLITE_OK, let opened else {
            let message = opened.map { String(cString: sqlite3_errmsg($0)) } ?? "sqlite3_open_v2 failed (\(result))"
            sqlite3_close_v2(opened)
            throw SQLiteError.open(message)
        }
        handle = opened
    }

    deinit {
        for statement in statements.values {
            sqlite3_finalize(statement)
        }
        sqlite3_close_v2(handle)
    }

    var lastErrorMessage: String {
        guard let handle else { return "no connection" }
        return String(cString: sqlite3_errmsg(handle))
    }

    /// Returns a cached prepared statement for `sql`, reset and with bindings cleared.
    func statement(for sql: String) throws -> OpaquePointer {
        if let cached = statements[sql] {
            sqlite3_reset(cached)
            sqlite3_clear_bindings(cached)
            return cached
        }
        var prepared: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &prepared, nil) == SQLITE_OK, let prepared else {
            throw SQLiteError.prepare(lastErrorMessage)
        }
        statements[sql] = prepared
        return prepared
    }

    func bind(_ text: String, to index: Int32, in statement: OpaquePointer) throws {
        guard sqlite3_bind_text(statement, index, text, -1, Self.transientDestructor) == SQLITE_OK else {
            throw SQLiteError.bind(lastErrorMessage)
        }
    }

    func bind(_ value: Int, to index: Int32, in statement: OpaquePointer) throws {
        guard sqlite3_bind_int64(statement, index, sqlite3_int64(value)) == SQLITE_OK else {
            throw SQLiteError.bind(lastErrorMessage)
        }
    }

    /// Steps once. `true` when a row is available, `false` when the statement is done.
    func step(_ statement: OpaquePointer) throws -> Bool {
        switch sqlite3_step(statement) {
        case SQLITE_ROW: return true
        case SQLITE_DONE:
            sqlite3_reset(statement)
            return false
        default:
            let message = lastErrorMessage
            sqlite3_reset(statement)
            throw SQLiteError.step(message)
        }
    }

    // MARK: Column readers

    func columnIsNull(_ statement: OpaquePointer, _ index: Int32) -> Bool {
        sqlite3_column_type(statement, index) == SQLITE_NULL
    }

    func int(_ statement: OpaquePointer, _ index: Int32) -> Int {
        Int(sqlite3_column_int64(statement, index))
    }

    func double(_ statement: OpaquePointer, _ index: Int32) -> Double? {
        columnIsNull(statement, index) ? nil : sqlite3_column_double(statement, index)
    }

    func text(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }
}
