import Foundation
import Testing
@testable import Omnomnom

/// The notice Today raises when Health is refusing nutrition. It is a claim about what
/// Health allows now, so it is made from the live authorization and never from entries
/// that failed to reach Health at some point in the past.
struct TodayViewModelTests {
    private func authorization(available: Bool = true, authorized: Set<Nutrient> = []) -> HealthAuthorization {
        HealthAuthorization(isAvailable: available, authorized: authorized)
    }

    @Test func noticeRisesWhenHealthAcceptsNothing() {
        let model = TodayViewModel()
        model.noteHealthAuthorization(authorization(), hasEntries: true)
        #expect(model.showsUnauthorizedNotice)
    }

    @Test func noticeStaysDownWhenHealthAcceptsSomething() {
        let model = TodayViewModel()
        model.noteHealthAuthorization(authorization(authorized: [.energy]), hasEntries: true)
        #expect(!model.showsUnauthorizedNotice)
    }

    /// Nothing can be written on a device without Health either, but there is nothing
    /// the user could switch on, so the notice would only be noise.
    @Test func noticeStaysDownWhenHealthIsUnavailable() {
        let model = TodayViewModel()
        model.noteHealthAuthorization(authorization(available: false), hasEntries: true)
        #expect(!model.showsUnauthorizedNotice)
    }

    @Test func noticeStaysDownOnADayWithNoEntries() {
        let model = TodayViewModel()
        model.noteHealthAuthorization(authorization(), hasEntries: false)
        #expect(!model.showsUnauthorizedNotice)
    }

    /// Once per launch: dismissing it holds for every further day the user pages through.
    @Test func noticeIsNotRaisedASecondTime() {
        let model = TodayViewModel()
        model.noteHealthAuthorization(authorization(), hasEntries: true)
        model.showsUnauthorizedNotice = false
        model.noteHealthAuthorization(authorization(), hasEntries: true)
        #expect(!model.showsUnauthorizedNotice)
    }
}
