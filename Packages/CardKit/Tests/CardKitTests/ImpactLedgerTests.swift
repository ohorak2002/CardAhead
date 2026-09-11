import XCTest
@testable import CardKit

/// Whether the app's own advice was any use, and what it is allowed to claim
/// about that.
final class ImpactLedgerTests: XCTestCase {

    private let engine = RecommendationEngine()
    private let now = Fixture.inQ3

    private func later(_ hours: Int, than date: Date? = nil) -> Date {
        (date ?? now).addingTimeInterval(TimeInterval(hours) * 3600)
    }

    private func makeSnapshot(
        cards: [Card] = [CardCatalog.amexGold, CardCatalog.citiDoubleCash],
        category: SpendingCategory = .dining,
        at date: Date? = nil
    ) throws -> RecommendationSnapshot {
        let context = PurchaseContext(
            category: category,
            merchantName: "XYZ Restaurant",
            confidence: .exact,
            date: date ?? now
        )
        let recommendation = try XCTUnwrap(engine.recommend(from: cards, in: context))
        return RecommendationSnapshot(recommendation, context: context)
    }

    // MARK: - The life of one suggestion

    func testASuggestionIsNotWorthAskingAboutUntilItHasBeenShown() throws {
        var ledger = ImpactLedger()
        let snapshot = try makeSnapshot()
        ledger.recordGenerated(snapshot)

        XCTAssertEqual(ledger.count(of: .recommendationGenerated), 1)
        XCTAssertNil(ledger.followUp(asOf: now))
    }

    func testOnceShownItBecomesTheQuestionToAsk() throws {
        var ledger = ImpactLedger()
        let snapshot = try makeSnapshot()
        ledger.recordGenerated(snapshot)
        ledger.recordShown(snapshot, at: now)

        let followUp = try XCTUnwrap(ledger.followUp(asOf: later(1)))
        XCTAssertEqual(followUp.snapshot.id, snapshot.id)
        XCTAssertEqual(followUp.snapshot.followUpDescription, "Amex Gold for dining")
    }

    /// One question, never a queue: a list of six "did you use these?" is a
    /// chore, and the newest is the only one anybody can actually remember.
    func testOnlyTheNewestSuggestionIsAskedAbout() throws {
        var ledger = ImpactLedger()
        let first = try makeSnapshot(category: .dining)
        let second = try makeSnapshot(category: .groceries, at: later(2))
        ledger.recordShown(first, at: now)
        ledger.recordShown(second, at: later(2))

        let followUp = try XCTUnwrap(ledger.followUp(asOf: later(3)))
        XCTAssertEqual(followUp.snapshot.id, second.id)
    }

    func testASuggestionFromLastWeekIsNotAMemoryTest() throws {
        var ledger = ImpactLedger()
        let snapshot = try makeSnapshot()
        ledger.recordShown(snapshot, at: now)
        XCTAssertNil(ledger.followUp(asOf: later(48)))
    }

    /// Saying no is a complete answer, and the question goes away.
    func testDecliningClosesTheQuestion() throws {
        var ledger = ImpactLedger()
        let snapshot = try makeSnapshot()
        ledger.recordShown(snapshot, at: now)
        ledger.recordAnswer(.recommendationDeclined, for: snapshot.id, at: later(1))

        XCTAssertNil(ledger.followUp(asOf: later(2)))
        XCTAssertEqual(ledger.count(of: .recommendationDeclined), 1)
    }

    /// Saying yes stops the question being asked again, but does not finish
    /// with the suggestion: what did you spend is still unasked, and always
    /// optional.
    func testAcceptingStopsAskingButLeavesTheAmountPriceable() throws {
        var ledger = ImpactLedger()
        let snapshot = try makeSnapshot()
        ledger.recordShown(snapshot, at: now)
        ledger.recordAnswer(.recommendationAccepted, for: snapshot.id, at: later(1))

        XCTAssertNil(ledger.followUp(asOf: later(2)))
        XCTAssertEqual(ledger.count(of: .recommendationAccepted), 1)
        XCTAssertNotNil(ledger.recordPurchase(85, for: snapshot.id, at: later(2)))
    }

    /// Somebody who said yes and then never got round to a number has not
    /// ignored anything, and must not be counted as having done.
    func testAnAcceptedSuggestionNobodyPricedIsNotCountedAsIgnored() throws {
        var ledger = ImpactLedger()
        let snapshot = try makeSnapshot()
        ledger.recordShown(snapshot, at: now)
        ledger.recordAnswer(.recommendationAccepted, for: snapshot.id, at: later(1))
        ledger.expireStale(asOf: later(30))

        XCTAssertEqual(ledger.count(of: .recommendationIgnored), 0)
        XCTAssertTrue(ledger.open.isEmpty)
    }

    func testAnAmountClosesItAndProducesAnEstimate() throws {
        var ledger = ImpactLedger()
        let snapshot = try makeSnapshot()
        ledger.recordShown(snapshot, at: now)
        ledger.recordAnswer(.recommendationAccepted, for: snapshot.id, at: later(1))

        let estimate = try XCTUnwrap(ledger.recordPurchase(85, for: snapshot.id, at: later(1)))
        XCTAssertEqual(estimate.incrementalValueCents ?? 0, 170, accuracy: 0.0001)
        XCTAssertNil(ledger.followUp(asOf: later(2)))
        XCTAssertEqual(ledger.count(of: .purchaseAmountEntered), 1)
        XCTAssertEqual(ledger.count(of: .estimatedBenefitCalculated), 1)
    }

    func testAnAmountForASuggestionNobodyIsTrackingDoesNothing() throws {
        var ledger = ImpactLedger()
        XCTAssertNil(ledger.recordPurchase(85, for: UUID(), at: now))
        XCTAssertTrue(ledger.events.isEmpty)
    }

    /// Silence is data. Dropping it would flatter the acceptance rate by only
    /// ever counting the people who replied.
    func testSilenceIsRecordedWhenTheQuestionExpires() throws {
        var ledger = ImpactLedger()
        let snapshot = try makeSnapshot()
        ledger.recordShown(snapshot, at: now)
        ledger.expireStale(asOf: later(30))

        XCTAssertEqual(ledger.count(of: .recommendationIgnored), 1)
        XCTAssertNil(ledger.followUp(asOf: later(30)))
    }

    func testExpiringTwiceDoesNotCountTheSameSilenceTwice() throws {
        var ledger = ImpactLedger()
        let snapshot = try makeSnapshot()
        ledger.recordShown(snapshot, at: now)
        ledger.expireStale(asOf: later(30))
        ledger.expireStale(asOf: later(31))

        XCTAssertEqual(ledger.count(of: .recommendationIgnored), 1)
    }

    /// A reminder re-rendered against a wallet edit while it is still dwelling
    /// is a correction, not a second suggestion — see `RegionMonitor`.
    func testShowingTheSameSuggestionAgainDoesNotStackTwoQuestions() throws {
        var ledger = ImpactLedger()
        let snapshot = try makeSnapshot()
        ledger.recordShown(snapshot, at: now)
        ledger.recordShown(snapshot, at: later(1))

        XCTAssertEqual(ledger.open.count, 1)
    }

    // MARK: - Staying quiet

    func testStayingQuietIsRecordedToo() {
        var ledger = ImpactLedger()
        ledger.recordSuppressed(.throttled, category: .groceries, at: now)
        ledger.recordSuppressed(.noMeaningfulEdge, category: .dining, at: later(1))

        XCTAssertEqual(ledger.count(of: .recommendationSuppressed), 2)
        XCTAssertEqual(ledger.summary.quietRate, 1.0)
    }

    func testASuppressionCarriesNoCardBecauseNoneWasChosen() {
        var ledger = ImpactLedger()
        ledger.recordSuppressed(.noCards, category: .dining, at: now)
        XCTAssertNil(ledger.events.first?.cardProductID)
        XCTAssertEqual(ledger.events.first?.suppressionReason, .noCards)
    }

    // MARK: - Adding it up

    func testValueCreatedCountsOnlyWhatSomebodyConfirmed() throws {
        var ledger = ImpactLedger()
        let snapshot = try makeSnapshot()
        ledger.recordShown(snapshot, at: now)
        ledger.recordAnswer(.recommendationAccepted, for: snapshot.id, at: later(1))
        ledger.recordPurchase(85, for: snapshot.id, at: later(1))

        let summary = ledger.summary
        XCTAssertEqual(summary.priced, 1)
        XCTAssertEqual(summary.estimatedRewardValueCents, 340, accuracy: 0.0001)
        XCTAssertEqual(summary.estimatedIncrementalValueCents, 170, accuracy: 0.0001)
    }

    func testAnEmptyLedgerHasNoRateToReport() {
        let summary = ImpactLedger().summary
        XCTAssertNil(summary.acceptanceRate)
        XCTAssertNil(summary.quietRate)
        XCTAssertFalse(summary.hasAnythingToShow)
    }

    /// A rate over no answers is a number with nothing behind it, and 0%
    /// would read as a verdict rather than as an absence.
    func testTheAcceptanceRateWaitsForAnActualAnswer() throws {
        var ledger = ImpactLedger()
        let snapshot = try makeSnapshot()
        ledger.recordGenerated(snapshot)
        ledger.recordShown(snapshot, at: now)
        XCTAssertNil(ledger.summary.acceptanceRate)

        ledger.recordAnswer(.recommendationDeclined, for: snapshot.id, at: later(1))
        XCTAssertEqual(try XCTUnwrap(ledger.summary.acceptanceRate), 0, accuracy: 0.0001)
    }

    func testTheAcceptanceRateIsOverAnswersNotOverSuggestions() throws {
        var ledger = ImpactLedger()
        let yes = try makeSnapshot()
        let no = try makeSnapshot(category: .groceries, at: later(1))
        ledger.recordShown(yes, at: now)
        ledger.recordShown(no, at: later(1))
        ledger.recordAnswer(.recommendationAccepted, for: yes.id, at: later(2))
        ledger.recordAnswer(.recommendationDeclined, for: no.id, at: later(2))

        XCTAssertEqual(try XCTUnwrap(ledger.summary.acceptanceRate), 0.5, accuracy: 0.0001)
    }

    // MARK: - Housekeeping

    func testTheLedgerDoesNotGrowForever() {
        var ledger = ImpactLedger(maximumEvents: 10)
        for index in 0..<40 {
            ledger.record(ImpactEvent(
                kind: .benefitsViewed,
                date: now.addingTimeInterval(TimeInterval(index))
            ))
        }
        XCTAssertEqual(ledger.events.count, 10)
        // Oldest first out, so what is left is the most recent.
        XCTAssertEqual(ledger.events.first?.date, now.addingTimeInterval(30))
    }

    func testErasingLeavesNothingBehind() throws {
        var ledger = ImpactLedger()
        let snapshot = try makeSnapshot()
        ledger.recordShown(snapshot, at: now)
        ledger.erase()

        XCTAssertTrue(ledger.events.isEmpty)
        XCTAssertNil(ledger.followUp(asOf: now))
    }

    func testALedgerSurvivesBeingWrittenAndReadBack() throws {
        var ledger = ImpactLedger()
        let snapshot = try makeSnapshot()
        ledger.recordShown(snapshot, at: now)
        ledger.recordPurchase(85, for: snapshot.id, at: later(1))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(ImpactLedger.self, from: encoder.encode(ledger))

        XCTAssertEqual(restored, ledger)
        XCTAssertEqual(restored.summary.estimatedIncrementalValueCents, 170, accuracy: 0.0001)
    }

    // MARK: - What may leave the phone

    /// Nothing does today. The redaction is written and tested now so that the
    /// day something might, it is not a thing somebody has to remember.
    func testAnEventForAnalyticsCarriesNoWalletIdentityAndNoCardName() throws {
        var ledger = ImpactLedger()
        let snapshot = try makeSnapshot()
        ledger.recordShown(snapshot, at: now)
        ledger.recordPurchase(85, for: snapshot.id, at: later(1))

        let priced = try XCTUnwrap(ledger.events.last)
        XCTAssertNotNil(priced.cardID)
        XCTAssertEqual(priced.estimate?.cardName, "Amex Gold")

        let redacted = priced.redactedForAnalytics()
        XCTAssertNil(redacted.cardID)
        XCTAssertEqual(redacted.estimate?.cardName, "")
        XCTAssertEqual(redacted.estimate?.comparedWithCardName, "")
        // What survives is what makes the data answerable.
        XCTAssertEqual(redacted.cardProductID, "amex-gold")
        XCTAssertEqual(redacted.category, .dining)
        XCTAssertEqual(redacted.estimate?.incrementalValueCents ?? 0, 170, accuracy: 0.0001)
    }

    /// There is no merchant anywhere in this model, by construction. If this
    /// ever fails, somebody has added a field that turns a rewards app into a
    /// location history.
    func testNoEventCanCarryAMerchant() throws {
        var ledger = ImpactLedger()
        let snapshot = try makeSnapshot()
        ledger.recordShown(snapshot, at: now)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = try XCTUnwrap(String(data: encoder.encode(ledger.events), encoding: .utf8))
        XCTAssertFalse(json.lowercased().contains("xyz restaurant"))
        XCTAssertFalse(json.lowercased().contains("merchant"))
        XCTAssertFalse(json.lowercased().contains("latitude"))
    }

    func testARecordingServiceSeesWhatItIsGiven() {
        let service = RecordingAnalyticsService()
        service.record(ImpactEvent(kind: .cardAdded, date: now, cardProductID: "amex-gold"))
        XCTAssertEqual(service.events.count, 1)
        XCTAssertEqual(service.events.first?.cardProductID, "amex-gold")
    }
}
