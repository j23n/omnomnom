import Accessibility
import Foundation
import Observation
import os

/// Day selection, sheet state, the non-blocking banner and the entry actions for Today.
/// Copying yesterday into an empty day lives in `TodayViewModel+CopyYesterday`.
@Observable
final class TodayViewModel {
    var selectedDay: Date
    var isAddPresented = false
    var isDatePickerPresented = false
    /// The transient notice at the bottom; `show(banner:)` also takes it down again.
    var banner: String?
    /// Entry whose editor is up; `nil` when none.
    var editingEntry: LogEntry?
    /// Whether the once-per-launch notice that Health is refusing nutrition is on screen.
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

    /// Raises the notice the first time a day with entries is shown while Health is
    /// there and currently accepts no nutrient at all.
    ///
    /// The notice makes a present-tense claim, so it is made from what Health allows
    /// now rather than from the rows. An entry whose nutrients never reached Health is
    /// a settled fact about that entry, and may well predate a permission the user has
    /// since granted; reading the notice off such rows made it appear on every launch.
    func noteHealthAuthorization(_ authorization: HealthAuthorization, hasEntries: Bool) {
        guard hasEntries, authorization.isAvailable, authorization.authorized.isEmpty else { return }
        guard !unauthorizedNoticeShown else { return }
        unauthorizedNoticeShown = true
        showsUnauthorizedNotice = true
    }

    /// Opens the editor for one entry; clearing `editingEntry` closes it again.
    func edit(_ entry: LogEntry) {
        editingEntry = entry
    }

    /// Takes an edit's outcome: its banner, if it warrants one, and a fresh read of the
    /// day, whose samples in Health were just replaced.
    func finishedEdit(banner message: String?) {
        show(banner: message)
        healthRefresh += 1
    }

    /// Mirrors the delete to Health first; the row only goes when Health agreed or held nothing.
    func delete(_ entry: LogEntry, using logger: EntryLogger) async {
        let outcome = await logger.delete(entry)
        show(banner: outcome.bannerMessage)
        healthRefresh += 1
    }

    /// Writes the entry to Health under a bumped version and hands back what to tell the
    /// user. The editor is the only caller and shows it inside the sheet: a banner would
    /// go up on Today, underneath the sheet, where nobody would see it. The wording says
    /// what happened rather than "restored", since the entry may never have been there.
    func restore(_ entry: LogEntry, using logger: EntryLogger) async -> String {
        defer { healthRefresh += 1 }
        do {
            let result = try await logger.restore(entry)
            if result.healthError == nil, result.written.isEmpty {
                // Health took the write and saved nothing, which is what it does while
                // no nutrient may be written. `LogResult` speaks for a log that just
                // happened; here nothing was logged, only offered again.
                return "Health still isn't accepting nutrition. The entry is kept here."
            }
            return result.bannerMessage ?? "Wrote \(entry.foodName) to Health."
        } catch {
            AppLog.store.error("restore failed: \(error.localizedDescription, privacy: .public)")
            return "Could not write the entry to Health."
        }
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
