import XCTest
@testable import CardKit

/// How many reminders a day is too many, and whether a second one for the same
/// shop is ever worth sending.
final class ReminderThrottleTests: XCTestCase {

    private let morning = Fixture.makeDate(2026, 8, 15)
    private func hoursLater(_ hours: Int, from date: Date) -> Date {
        date.addingTimeInterval(TimeInterval(hours) * 3600)
    }

    // MARK: - Per-merchant dedup

    func testTheFirstReminderAtAShopIsAlwaysAllowed() {
        let throttle = ReminderThrottle()
        XCTAssertTrue(throttle.allows(merchantID: "cafe", at: morning))
    }

    func testASecondReminderAtTheSameShopTheSameDayIsRefused() {
        var throttle = ReminderThrottle()
        throttle.recordFired(merchantID: "cafe", at: morning)
        XCTAssertFalse(throttle.allows(merchantID: "cafe", at: hoursLater(2, from: morning)))
    }

    /// The dedup is per merchant, not global — a different shop the same
    /// afternoon is a different question.
    func testADifferentShopTheSameDayIsUnaffected() {
        var throttle = ReminderThrottle()
        throttle.recordFired(merchantID: "cafe", at: morning)
        XCTAssertTrue(throttle.allows(merchantID: "market", at: hoursLater(1, from: morning)))
    }

    func testTheSameShopTheNextDayIsAllowedAgain() {
        var throttle = ReminderThrottle()
        throttle.recordFired(merchantID: "cafe", at: morning)
        XCTAssertTrue(throttle.allows(merchantID: "cafe", at: hoursLater(25, from: morning)))
    }

    func testARaisedPerMerchantLimitAllowsMoreThanOne() {
        var throttle = ReminderThrottle(maxPerMerchantPerDay: 2)
        throttle.recordFired(merchantID: "cafe", at: morning)
        XCTAssertTrue(throttle.allows(merchantID: "cafe", at: hoursLater(1, from: morning)))
        throttle.recordFired(merchantID: "cafe", at: hoursLater(1, from: morning))
        XCTAssertFalse(throttle.allows(merchantID: "cafe", at: hoursLater(2, from: morning)))
    }

    // MARK: - The daily ceiling

    func testTheCeilingCountsAcrossDifferentShops() {
        var throttle = ReminderThrottle(maxPerDay: 2)
        throttle.recordFired(merchantID: "cafe", at: morning)
        throttle.recordFired(merchantID: "market", at: hoursLater(1, from: morning))
        XCTAssertFalse(throttle.allows(merchantID: "gas station", at: hoursLater(2, from: morning)))
    }

    func testTheCeilingResetsTheNextDay() {
        var throttle = ReminderThrottle(maxPerDay: 1)
        throttle.recordFired(merchantID: "cafe", at: morning)
        XCTAssertTrue(throttle.allows(merchantID: "market", at: hoursLater(25, from: morning)))
    }

    /// The ceiling is checked first: a brand-new shop still gets refused once
    /// the day is full, it is not exempt just for being the first time there.
    func testTheCeilingRefusesEvenAFirstVisitToANewShop() {
        var throttle = ReminderThrottle(maxPerDay: 1)
        throttle.recordFired(merchantID: "cafe", at: morning)
        XCTAssertFalse(throttle.allows(merchantID: "brand new place", at: hoursLater(1, from: morning)))
    }

    // MARK: - It does not grow forever

    func testOldEntriesAreForgottenOnWrite() {
        var throttle = ReminderThrottle()
        throttle.recordFired(merchantID: "cafe", at: morning)
        throttle.recordFired(merchantID: "market", at: hoursLater(72, from: morning))
        XCTAssertEqual(throttle.fired.count, 1, "the three-day-old entry should have been pruned")
        XCTAssertEqual(throttle.fired.first?.merchantID, "market")
    }
}
