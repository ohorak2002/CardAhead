import XCTest
@testable import CardKit

/// The parts of the notification policy that have to survive the app being
/// killed.
///
/// **This is not a theoretical concern here.** The app is launched in the
/// background by a geofence crossing, does its work in a few seconds, and is
/// suspended or terminated again — often between an arrival and the moment its
/// reminder is due. A daily budget that resets every time the process dies is
/// not a budget, and a cooldown that forgets is an app that reminds you about
/// the same coffee shop nine times on a walk.
final class NotificationPersistenceTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)

    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 15) -> Date {
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 8
        parts.day = day
        parts.hour = hour
        parts.minute = minute
        return calendar.date(from: parts) ?? Date()
    }

    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: try encoder.encode(value))
    }

    private func record(
        merchantID: String = "m",
        category: SpendingCategory = .dining,
        identity: String = "k",
        sent: Bool = true,
        at date: Date
    ) -> NotificationRecord {
        NotificationRecord(
            date: date,
            merchantID: merchantID,
            category: category,
            identityKey: identity,
            score: 70,
            band: .normal,
            wasSent: sent
        )
    }

    // MARK: - Across a restart

    func testTheDaysBudgetSurvivesARestart() throws {
        var before = NotificationHistory()
        before.record(record(merchantID: "a", at: at(8)))
        before.record(record(merchantID: "b", category: .gas, at: at(9)))
        before.record(record(merchantID: "c", category: .groceries, at: at(10)))

        let after = try roundTrip(before)
        XCTAssertEqual(after.sentCount(on: at(12), calendar: calendar), 3)
    }

    func testACooldownSurvivesARestart() throws {
        var before = NotificationHistory()
        before.record(record(merchantID: "bistro", at: at(11, 30)))

        let after = try roundTrip(before)
        XCTAssertEqual(after.lastSent(merchantID: "bistro")?.date, at(11, 30))
        XCTAssertNotNil(after.lastSent(category: .dining))
    }

    func testADuplicateIsStillADuplicateAfterARestart() throws {
        let identity = RecommendationIdentity(
            merchantID: "bistro", category: .dining, cardID: UUID(),
            appliedRate: 4, hasActivationNudge: false
        )
        var before = NotificationHistory()
        before.record(record(identity: identity.key, at: at(11)))

        let after = try roundTrip(before)
        XCTAssertTrue(after.hasSent(identity: identity, since: at(9)))
    }

    func testTheWholePolicySurvivesARestart() throws {
        var before = NotificationPolicy(intensity: .minimal)
        before.setCategory(.dining, enabled: false)
        before.quietHours = QuietHours(startHour: 21, endHour: 9)
        before.mute(merchantID: "noisy", for: .week, from: at(12), calendar: calendar)

        let after = try roundTrip(before)
        XCTAssertEqual(after.intensity, .minimal)
        XCTAssertFalse(after.allows(category: .dining))
        XCTAssertTrue(after.quietHours.contains(at(22), calendar: calendar))
        XCTAssertTrue(after.isMuted(merchantID: "noisy", at: at(12, 0, day: 18)))
    }

    /// Everything the policy holds must be `Codable` without a custom coder.
    /// A field that silently fails to encode is a limit that silently stops
    /// being enforced.
    func testEveryIntensityAndBandRoundTrips() throws {
        for intensity in NotificationIntensity.allCases {
            XCTAssertEqual(try roundTrip(NotificationPolicy(intensity: intensity)).intensity, intensity)
        }
        for band in NotificationBand.allCases {
            XCTAssertEqual(try roundTrip(band), band)
        }
        for feedback in NotificationFeedback.allCases {
            XCTAssertEqual(try roundTrip(feedback), feedback)
        }
        for reason in SuppressionReason.allCases {
            XCTAssertEqual(try roundTrip(reason), reason)
        }
    }

    // MARK: - A ledger written before this existed

    /// The app has been on a phone with an `impact.json` written before the
    /// notification layer existed. A snapshot in it has no `activationNudge`
    /// key, and a decoder that threw on that would lose the whole file.
    func testAnOlderSnapshotStillDecodes() throws {
        let json = """
        {
          "id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301",
          "date": "2026-08-15T12:00:00Z",
          "cardID": "3F2504E0-4F89-11D3-9A0C-0305E82C3302",
          "cardName": "Amex Gold",
          "currencyName": "Membership Rewards",
          "style": "points",
          "appliedRate": 4,
          "centsPerDollar": 4,
          "wasChosenForWelcomeBonus": false,
          "category": "dining",
          "confidence": "exact"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(
            RecommendationSnapshot.self, from: Data(json.utf8)
        )

        XCTAssertNil(snapshot.activationNudge)
        // Nobody knowing is not the same as it having been there. The safe
        // reading is no, and the score must not award the nudge bonus for it.
        XCTAssertFalse(snapshot.hadActivationNudge)
    }

    // MARK: - Pruning

    /// The retention window has to outlast the longest thing that asks about
    /// it, or Minimal's three-day merchant cooldown would quietly stop working
    /// on day two.
    func testRetentionOutlastsTheLongestCooldown() {
        let longest = NotificationIntensity.allCases
            .map(\.thresholds.merchantCooldown)
            .max() ?? 0
        XCTAssertGreaterThan(NotificationHistory.retention, longest)
    }

    func testAnUnusualDayCannotGrowTheFileWithoutLimit() {
        var history = NotificationHistory()
        for minute in 0..<(NotificationHistory.maximumRecords + 50) {
            history.record(record(
                merchantID: "m\(minute)",
                identity: "k\(minute)",
                at: at(0).addingTimeInterval(Double(minute) * 60)
            ))
        }
        XCTAssertEqual(history.records.count, NotificationHistory.maximumRecords)
        // The newest survive, because those are the ones a cooldown asks
        // about.
        XCTAssertEqual(history.records.last?.merchantID, "m\(NotificationHistory.maximumRecords + 49)")
    }

    // MARK: - Correcting a row

    /// The wallet can change in the moment between the ranking engine saying
    /// there is something to say and the notification centre being handed it.
    /// The row is already written by then, and leaving it would charge the
    /// day's budget for a reminder nobody will ever see.
    func testARowTakenBackStopsCountingAgainstTheBudget() {
        var history = NotificationHistory()
        let row = record(at: at(11))
        history.record(row)
        XCTAssertEqual(history.sentCount(on: at(12), calendar: calendar), 1)

        history.markNotSent(recordID: row.id, reason: .noMeaningfulEdge)
        XCTAssertEqual(history.sentCount(on: at(12), calendar: calendar), 0)
        // Still there, so the lab can show that something was considered.
        XCTAssertEqual(history.records.count, 1)
        XCTAssertEqual(history.records.first?.suppression, .noMeaningfulEdge)
    }

    /// Leaving before the dwell completes cancels the reminder. Nothing was
    /// sent, so nothing may be charged — the record of the arrival lives in
    /// the impact ledger, not in the budget.
    func testAnArrivalThatWasCancelledNeverEntersTheBudget() {
        var history = NotificationHistory()
        history.record(record(sent: false, at: at(11)))
        XCTAssertEqual(history.sentCount(on: at(12), calendar: calendar), 0)
        XCTAssertNil(history.lastSent(merchantID: "m"))
        XCTAssertNil(history.lastSent(category: .dining))
    }

    // MARK: - Feedback

    func testAnAnswerSurvivesARestart() throws {
        var before = NotificationHistory()
        let row = record(at: at(11))
        before.record(row)
        before.note(.notHere, forRecordID: row.id)

        let after = try roundTrip(before)
        XCTAssertEqual(after.records.first?.feedback, .notHere)
    }

    /// Three answers about three different things. Collapsing any two would
    /// produce a signal nobody can act on.
    func testTheThreeAnswersStayDistinct() {
        XCTAssertEqual(Set(NotificationFeedback.allCases.map(\.rawValue)).count, 3)
        XCTAssertEqual(NotificationFeedback(rawValue: "usedIt"), .usedIt)
        XCTAssertEqual(NotificationFeedback(rawValue: "notHere"), .notHere)
        XCTAssertNil(NotificationFeedback(rawValue: "com.apple.UNNotificationDefaultActionIdentifier"))
    }
}
