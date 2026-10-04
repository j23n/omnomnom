import Foundation
import SwiftData

/// One date, and what the user said about it.
///
/// Created only when there is something to record, so a store full of untouched days
/// stays empty.
///
/// It holds no sample membership. The cadence derives that from the date, and a complete
/// day counts toward every mean whether or not the schedule asked for it, so there would
/// be nothing for a stored flag to decide. Marking a day complete is one tap on Today and it is the entire
/// mechanism behind a defensible average: every figure on Trends says what it rests on,
/// as "mean of 19 complete days", never as a bare number over a range.
///
/// Schema rules as elsewhere: no unique attributes, everything defaulted, which means
/// `day` is resolved in code and `record(for:)` is the only way one is found.
@Model
final class DayRecord {
    var id: UUID = UUID()
    /// Midnight at the start of the day this describes, in the current calendar.
    var day: Date = Date.now
    /// The user said this is everything they ate that day.
    var isComplete: Bool = false

    init(day: Date) {
        self.id = UUID()
        self.day = day
        self.isComplete = false
    }

    /// The record for a day, or `nil` when nothing has been said about it.
    static func record(for day: Date, in context: ModelContext, calendar: Calendar = .current) throws -> DayRecord? {
        let start = calendar.startOfDay(for: day)
        let next = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        var descriptor = FetchDescriptor<DayRecord>(
            predicate: #Predicate<DayRecord> { $0.day >= start && $0.day < next }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// The record for a day, creating one if there is none.
    static func ensure(for day: Date, in context: ModelContext, calendar: Calendar = .current) throws -> DayRecord {
        if let existing = try record(for: day, in: context, calendar: calendar) { return existing }
        let record = DayRecord(day: calendar.startOfDay(for: day))
        context.insert(record)
        return record
    }

    /// Every record in a range, by day, for the coverage strip.
    static func records(
        from start: Date, to end: Date, in context: ModelContext, calendar: Calendar = .current
    ) throws -> [Date: DayRecord] {
        let first = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        let found = try context.fetch(
            FetchDescriptor<DayRecord>(
                predicate: #Predicate<DayRecord> { $0.day >= first && $0.day <= last },
                sortBy: [SortDescriptor(\DayRecord.day)]
            )
        )
        return Dictionary(found.map { (calendar.startOfDay(for: $0.day), $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Marks or unmarks a day, creating the record on the first mark. Unmarking a day
    /// that has no record is nothing to do.
    static func setComplete(
        _ complete: Bool, for day: Date, in context: ModelContext, calendar: Calendar = .current
    ) throws {
        if !complete, try record(for: day, in: context, calendar: calendar) == nil { return }
        try ensure(for: day, in: context, calendar: calendar).isComplete = complete
    }
}
