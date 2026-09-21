import Foundation
import Observation
import os

/// Day selection, sheet state, the non-blocking banner and the Health actions for Today.
@Observable
final class TodayViewModel {
    var selectedDay: Date
    var isAddPresented = false
    var isDatePickerPresented = false
    var banner: String?
    /// Entry whose Health actions dialog is up; `nil` when none.
    var healthActionEntry: LogEntry?
    /// Whether the once-per-launch notice about unauthorized entries is on screen.
    var showsUnauthorizedNotice = false
    /// Bumped whenever the day's Health samples should be read again.
    private(set) var healthRefresh = 0

    private let calendar: Calendar
    /// Start of the day that was "today" when the scene last became active.
    private var lastActivatedDay: Date
    private var unauthorizedNoticeShown = false

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
    /// what was "today" last time, follow the calendar to the new day. Health samples
    /// are read again either way, since the user may have been in the Health app.
    func sceneBecameActive(now: Date = .now) {
        let today = calendar.startOfDay(for: now)
        if selectedDay == lastActivatedDay, today != lastActivatedDay {
            selectedDay = today
        }
        lastActivatedDay = today
        healthRefresh += 1
    }

    /// Shows the banner for a completed log, if the result warrants one.
    func handle(_ result: LogResult) {
        banner = result.bannerMessage
    }

    /// Raises the unauthorized notice the first time a day shows such an entry.
    func noteUnauthorizedEntries(_ hasAny: Bool) {
        guard hasAny, !unauthorizedNoticeShown else { return }
        unauthorizedNoticeShown = true
        showsUnauthorizedNotice = true
    }

    func presentHealthActions(for entry: LogEntry) {
        healthActionEntry = entry
    }

    /// Mirrors the delete to Health first; the row only goes when Health agreed or held nothing.
    func delete(_ entry: LogEntry, using logger: EntryLogger) async {
        let outcome = await logger.delete(entry)
        banner = outcome.bannerMessage
        healthRefresh += 1
    }

    /// Writes the entry to Health again under a bumped version.
    func restore(_ entry: LogEntry, using logger: EntryLogger) async {
        do {
            let result = try await logger.restore(entry)
            banner = result.bannerMessage ?? "Restored \(entry.foodName) to Health."
        } catch {
            AppLog.store.error("restore failed: \(error.localizedDescription, privacy: .public)")
            banner = "Could not restore the entry."
        }
        healthRefresh += 1
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
