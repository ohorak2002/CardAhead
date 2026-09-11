import XCTest
@testable import CardKit

/// The dwell rule. None of this can be exercised on a device without walking
/// in and out of real shops, which is exactly why all of it lives in a value
/// type with an injected clock.
final class ArrivalTrackerTests: XCTestCase {

    private let noon = Fixture.inQ3
    private lazy var bistro = Fixture.region(
        Fixture.merchant("bistro", category: .dining, metersNorth: 40, name: "Corner Bistro")
    )
    private lazy var market = Fixture.region(
        Fixture.merchant("market", category: .groceries, metersNorth: 90, name: "Hill Market")
    )

    private func at(_ minutes: Double) -> Date {
        noon.addingTimeInterval(minutes * 60)
    }

    // MARK: - The delay

    func testEnteringStartsAClockRatherThanANotification() {
        var tracker = ArrivalTracker()
        let arrival = tracker.enter(bistro, at: noon)
        XCTAssertEqual(arrival?.merchant.name, "Corner Bistro")
        XCTAssertEqual(arrival?.confirmAt, at(4))
        XCTAssertEqual(tracker.pending.count, 1)
        XCTAssertFalse(arrival?.isDue(asOf: at(3)) ?? true)
    }

    func testDelayIsClampedIntoTheThreeToFiveMinuteWindow() {
        XCTAssertEqual(ArrivalTracker(confirmationDelay: 0).confirmationDelay, 180)
        XCTAssertEqual(ArrivalTracker(confirmationDelay: 60 * 60).confirmationDelay, 300)
        XCTAssertEqual(ArrivalTracker(confirmationDelay: 200).confirmationDelay, 200)
    }

    /// iOS re-reports an entry as the location fix wobbles over the boundary.
    /// Restarting the clock each time would mean a reminder that never arrives.
    func testASecondEntryForTheSameRegionDoesNotRestartTheClock() {
        var tracker = ArrivalTracker()
        tracker.enter(bistro, at: noon)
        let repeated = tracker.enter(bistro, at: at(2))
        XCTAssertNil(repeated)
        XCTAssertEqual(tracker.pending.count, 1)
        XCTAssertEqual(tracker.arrival(forRegionID: bistro.id)?.confirmAt, at(4))
    }

    // MARK: - Leaving

    func testLeavingBeforeTheClockRunsOutCancelsSilently() {
        var tracker = ArrivalTracker()
        tracker.enter(bistro, at: noon)
        let cancelled = tracker.exit(regionID: bistro.id, at: at(1.5))
        XCTAssertEqual(cancelled?.regionID, bistro.id)
        XCTAssertTrue(tracker.pending.isEmpty)
        XCTAssertNil(tracker.confirm(regionID: bistro.id, at: at(4)))
    }

    /// iOS reports exits for regions whose entry we never saw — after a
    /// relaunch, or for a region registered by a previous run.
    func testLeavingARegionWeWereNotWaitingOnIsHarmless() {
        var tracker = ArrivalTracker()
        XCTAssertNil(tracker.exit(regionID: bistro.id, at: noon))
        XCTAssertTrue(tracker.pending.isEmpty)
    }

    func testLeavingOneRegionLeavesTheOtherPending() {
        var tracker = ArrivalTracker()
        tracker.enter(bistro, at: noon)
        tracker.enter(market, at: noon)
        tracker.exit(regionID: bistro.id, at: at(1))
        XCTAssertEqual(tracker.pending.map(\.regionID), [market.id])
    }

    // MARK: - Confirming

    func testConfirmingEarlyChangesNothing() {
        var tracker = ArrivalTracker()
        tracker.enter(bistro, at: noon)
        XCTAssertNil(tracker.confirm(regionID: bistro.id, at: at(2)))
        XCTAssertEqual(tracker.pending.count, 1, "an early confirm must not consume the arrival")
    }

    func testConfirmingWhenDueHandsBackTheArrivalOnce() {
        var tracker = ArrivalTracker()
        tracker.enter(bistro, at: noon)
        XCTAssertEqual(tracker.confirm(regionID: bistro.id, at: at(4))?.merchant.name, "Corner Bistro")
        XCTAssertTrue(tracker.pending.isEmpty)
        XCTAssertNil(tracker.confirm(regionID: bistro.id, at: at(5)))
    }

    /// A scheduled notification can fire a fraction early. Rejecting it would
    /// drop the arrival entirely, because nothing reschedules it.
    func testAFireASecondEarlyStillCounts() {
        var tracker = ArrivalTracker()
        tracker.enter(bistro, at: noon)
        XCTAssertNotNil(tracker.confirm(regionID: bistro.id, at: at(4).addingTimeInterval(-2)))
    }

    func testDueArrivalsComeBackOldestFirstAndOnlyOnce() {
        var tracker = ArrivalTracker()
        tracker.enter(market, at: noon)
        tracker.enter(bistro, at: noon.addingTimeInterval(-60))
        let due = tracker.confirmDue(asOf: at(4))
        XCTAssertEqual(due.map(\.regionID), [bistro.id, market.id])
        XCTAssertTrue(tracker.pending.isEmpty)
        XCTAssertTrue(tracker.confirmDue(asOf: at(10)).isEmpty)
    }

    func testDueArrivalsLeaveTheNotYetDueAlone() {
        var tracker = ArrivalTracker()
        tracker.enter(bistro, at: noon)
        tracker.enter(market, at: at(3))
        XCTAssertEqual(tracker.confirmDue(asOf: at(4)).map(\.regionID), [bistro.id])
        XCTAssertEqual(tracker.pending.map(\.regionID), [market.id])
    }

    // MARK: - Housekeeping

    /// An entry whose exit never arrived — phone off, or driven out of range
    /// faster than iOS noticed — is still due, however late the app gets round
    /// to looking, and is still reported at the time it actually came due.
    func testAnArrivalNoticedDaysLateKeepsItsOwnTime() {
        var tracker = ArrivalTracker()
        tracker.enter(bistro, at: noon)
        let due = tracker.confirmDue(asOf: at(60 * 24 * 3))
        XCTAssertEqual(due.map(\.confirmAt), [at(4)])
        XCTAssertTrue(tracker.pending.isEmpty)
    }

    /// After the plan is redrawn, a pending arrival for a region we no longer
    /// watch can never receive its exit, so it is dropped with the region.
    func testArrivalsOutsideTheNewPlanAreDropped() {
        var tracker = ArrivalTracker()
        tracker.enter(bistro, at: noon)
        tracker.enter(market, at: noon)
        let dropped = tracker.dropArrivals(outside: [market.id])
        XCTAssertEqual(dropped.map(\.regionID), [bistro.id])
        XCTAssertEqual(tracker.pending.map(\.regionID), [market.id])
    }

    /// The app is routinely killed between the entry and the confirmation, so
    /// the pending list has to survive on disk.
    func testTrackerSurvivesARoundTripThroughJSON() throws {
        var tracker = ArrivalTracker()
        tracker.enter(bistro, at: noon)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var restored = try decoder.decode(ArrivalTracker.self, from: encoder.encode(tracker))
        XCTAssertEqual(restored.pending.map(\.regionID), [bistro.id])
        XCTAssertEqual(restored.confirm(regionID: bistro.id, at: at(4))?.merchant.name, "Corner Bistro")
    }
}
