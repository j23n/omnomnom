import Foundation
import Observation
import os

/// Day selection, sheet state and the non-blocking banner for Today.
@Observable
final class TodayViewModel {
    var selectedDay: Date
    var isAddPresented = false
    var isDatePickerPresented = false
    var banner: String?

    private let calendar: Calendar
    /// Start of the day that was "today" when the scene last became active.
    private var lastActivatedDay: Date

    init(calendar: Calendar = .current) {
        self.calendar = calendar
        let today = calendar.startOfDay(for: Date.now)
        self.selectedDay = today
        self.lastActivatedDay = today
    }

    var dayTitle: String {
        Formatters.dayTitle(selectedDay, calendar: calendar)
    }

    func showPreviousDay() {
        shiftDay(by: -1)
    }

    func showNextDay() {
        shiftDay(by: 1)
    }

    func select(day: Date) {
        selectedDay = calendar.startOfDay(for: day)
    }

    /// Midnight rollover: when the scene comes back and the user was still looking at
    /// what was "today" last time, follow the calendar to the new day.
    func sceneBecameActive(now: Date = .now) {
        let today = calendar.startOfDay(for: now)
        if selectedDay == lastActivatedDay, today != lastActivatedDay {
            selectedDay = today
        }
        lastActivatedDay = today
    }

    /// Shows the banner for a completed log, if the result warrants one.
    func handle(_ result: LogResult) {
        banner = result.bannerMessage
    }

    /// Mirrors the delete to Health first; the row only goes when Health agreed or held nothing.
    func delete(_ entry: LogEntry, using logger: EntryLogger) async {
        let outcome = await logger.delete(entry)
        banner = outcome.bannerMessage
    }

    /// Re-logs the same food and amount at the current time.
    func repeatEntry(_ entry: LogEntry, using logger: EntryLogger) async {
        guard let food = entry.food else {
            banner = "This food is no longer available to repeat."
            return
        }
        let now = Date.now
        do {
            let result = try await logger.log(food: food, grams: entry.grams, mealSlot: MealSlot.inferred(from: now), at: now)
            banner = result.bannerMessage ?? "Logged \(entry.foodName) again."
        } catch {
            AppLog.store.error("repeat failed: \(error.localizedDescription, privacy: .public)")
            banner = "Could not log the entry again."
        }
    }

    private func shiftDay(by days: Int) {
        if let next = calendar.date(byAdding: .day, value: days, to: selectedDay) {
            selectedDay = calendar.startOfDay(for: next)
        }
    }
}
