import Accessibility
import Foundation
import Observation
import os

/// Day selection, sheet state, the non-blocking banner and the Health actions for Today.
/// Copying yesterday into an empty day lives in `TodayViewModel+CopyYesterday`.
@Observable
final class TodayViewModel {
    var selectedDay: Date
    var isAddPresented = false
    var isDatePickerPresented = false
    /// The transient notice at the bottom; `show(banner:)` also takes it down again.
    var banner: String?
    /// Entry whose Health actions dialog is up; `nil` when none.
    var healthActionEntry: LogEntry?
    /// Whether the once-per-launch notice about unauthorized entries is on screen.
    var showsUnauthorizedNotice = false
    /// Bumped whenever the day's Health samples should be read again.
    private(set) var healthRefresh = 0

    let calendar: Calendar
    /// Start of the day that was "today" when the scene last became active.
    private var lastActivatedDay: Date
    private var unauthorizedNoticeShown = false
    private var bannerDismissal: Task<Void, Never>?

    init(calendar: Calendar = .current) {
        self.calendar = calendar
        let today = calendar.startOfDay(for: Date.now)
        self.selectedDay = today
        self.lastActivatedDay = today
    }

    var dayTitle: String {
        Formatters.dayTitle(selectedDay, calendar: calendar)
    }

    var daySubtitle: String {
        Formatters.daySubtitle(selectedDay, calendar: calendar)
    }

    var isShowingToday: Bool {
        calendar.isDateInToday(selectedDay)
    }

    func showPreviousDay() {
        shiftDay(by: -1)
    }

    func showNextDay() {
        shiftDay(by: 1)
    }

    func showToday() {
        select(day: Date.now)
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

    /// Puts a banner up, tells VoiceOver, and takes it down after four seconds unless a
    /// newer one replaces it or the user dismisses it first. `nil` clears the banner.
    func show(banner message: String?) {
        bannerDismissal?.cancel()
        banner = message
        guard let message else { return }
        AccessibilityNotification.Announcement(message).post()
        bannerDismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.banner = nil
        }
    }

    func dismissBanner() {
        show(banner: nil)
    }

    /// Shows the banner for a completed log, if the result warrants one.
    func handle(_ result: LogResult) {
        show(banner: result.bannerMessage)
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
        show(banner: outcome.bannerMessage)
        healthRefresh += 1
    }

    /// Writes the entry to Health again under a bumped version.
    func restore(_ entry: LogEntry, using logger: EntryLogger) async {
        do {
            let result = try await logger.restore(entry)
            show(banner: result.bannerMessage ?? "Restored \(entry.foodName) to Health.")
        } catch {
            AppLog.store.error("restore failed: \(error.localizedDescription, privacy: .public)")
            show(banner: "Could not restore the entry.")
        }
        healthRefresh += 1
    }

    /// Re-logs the same item and amount at the current time, from the entry's snapshot.
    func repeatEntry(_ entry: LogEntry, using logger: EntryLogger) async {
        do {
            let result = try await logger.repeatEntry(entry, at: Date.now)
            show(banner: result.bannerMessage ?? "Logged \(entry.foodName) again.")
        } catch {
            AppLog.store.error("repeat failed: \(error.localizedDescription, privacy: .public)")
            show(banner: "Could not log the entry again.")
        }
    }

    private func shiftDay(by days: Int) {
        if let next = calendar.date(byAdding: .day, value: days, to: selectedDay) {
            selectedDay = calendar.startOfDay(for: next)
        }
    }
}
