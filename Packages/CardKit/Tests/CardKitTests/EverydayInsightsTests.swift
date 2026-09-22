import XCTest
@testable import CardKit

final class EverydayInsightsTests: XCTestCase {
    func testOrganizationRoundTripKeepsWalletAndRecommendationUnchanged() throws {
        let cards = [CardCatalog.amexGold, CardCatalog.citiDoubleCash]
        let before = try JSONEncoder().encode(cards)
        let context = PurchaseContext(category: .dining, date: Fixture.inQ3)
        let recommendation = RecommendationEngine().recommend(from: cards, in: context)
        var preferences = WalletOrganization()
        preferences.setNickname("  Dinner card  ", for: cards[0].id)
        preferences.hiddenCardIDs.insert(cards[0].id)
        preferences.monthlyGoalDollars = Decimal(string: "42.50")
        let restored = try JSONDecoder().decode(WalletOrganization.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(restored, preferences)
        XCTAssertEqual(restored.name(for: cards[0]), "Dinner card")
        XCTAssertEqual(restored.visibleCards(in: cards).map(\.id), [cards[1].id])
        XCTAssertEqual(try JSONDecoder().decode([Card].self, from: before), cards)
        XCTAssertEqual(RecommendationEngine().recommend(from: cards, in: context), recommendation)
        preferences.setNickname(" \n ", for: cards[0].id)
        XCTAssertEqual(preferences.name(for: cards[0]), cards[0].displayName)
    }

    func testGoalParsingRejectsPartialOrInvalidAmounts() {
        XCTAssertEqual(WalletOrganization.goal(from: "42.50"), Decimal(string: "42.50"))
        XCTAssertEqual(WalletOrganization.goal(from: " 42,50 "), Decimal(string: "42.50"))
        for text in ["", "0", "-12", "100001", "12oops", "1.2.3", "NaN", "12.345", "1,000.00"] {
            XCTAssertNil(WalletOrganization.goal(from: text), text)
        }
    }

    func testDeadlinesDoNotInventCreditResetDatesOrUnannouncedQuarters() {
        var card = CardCatalog.amexGold
        card.welcomeBonus = nil
        card.rotatingProgram = RotatingProgram(rate: 5)
        XCTAssertTrue(EverydayInsights.deadlines(in: [card], asOf: Fixture.inQ3).isEmpty)
    }

    func testDeadlinesRespectActivationAndLastEligibleDay() throws {
        var card = CardCatalog.citiDoubleCash
        let quarter = Fixture.q3
        let activation = Fixture.makeDate(2026, 9, 15)
        card.rotatingProgram = RotatingProgram(rate: 5, quarters: [RotatingQuarter(quarter: quarter, categories: [.dining], activationDeadline: activation)], knownThrough: quarter)
        let rows = EverydayInsights.deadlines(in: [card], asOf: Fixture.inQ3)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.first?.date, activation)
        XCTAssertEqual(rows.last?.date, quarter.end().addingTimeInterval(-1))
        XCTAssertEqual(Calendar.current.component(.day, from: try XCTUnwrap(rows.last?.date)), 30)
        let afterActivation = EverydayInsights.deadlines(in: [card], asOf: Fixture.makeDate(2026, 9, 20))
        XCTAssertEqual(afterActivation.count, 1)
        XCTAssertFalse(try XCTUnwrap(afterActivation.first).needsActivation)
        XCTAssertTrue(EverydayInsights.deadlines(in: [card], asOf: quarter.end()).isEmpty)
    }

    func testCompletedAndExpiredSignupBonusesAreAbsent() {
        let card = Fixture.withWelcomeBonus(CardCatalog.amexGold, rewardUnits: 100, required: 1000, deadline: Fixture.makeDate(2026, 9, 1))
        XCTAssertEqual(EverydayInsights.deadlines(in: [card], asOf: Fixture.inQ3).count, 1)
        XCTAssertTrue(EverydayInsights.deadlines(in: [card], asOf: Fixture.makeDate(2026, 9, 2)).isEmpty)
        var met = card
        met.welcomeBonus?.spentDollars = 1000
        XCTAssertTrue(EverydayInsights.deadlines(in: [met], asOf: Fixture.inQ3).isEmpty)
    }

    func testUrgencyUsesCalendarDaysAcrossDaylightSavingTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 23)))
        let tomorrow = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12)))
        var row = BenefitDeadline(id: "test", cardID: UUID(), title: "", detail: "", date: tomorrow, needsActivation: false)
        XCTAssertEqual(row.urgency(asOf: now, calendar: calendar), "Ends tomorrow")
        row.date = now.addingTimeInterval(60)
        XCTAssertEqual(row.urgency(asOf: now, calendar: calendar), "Ends today")
        row.date = now.addingTimeInterval(-1)
        XCTAssertEqual(row.urgency(asOf: now, calendar: calendar), "Ended")
    }

    func testExplanationsReflectTheActualWinner() throws {
        let context = PurchaseContext(category: .dining, date: Fixture.inQ3)
        let engine = RecommendationEngine()
        let winner = try XCTUnwrap(engine.recommend(from: [CardCatalog.amexGold, CardCatalog.citiDoubleCash], in: context))
        XCTAssertTrue(winner.choiceExplanation.contains("Highest estimated value"))
        let only = try XCTUnwrap(engine.recommend(from: [CardCatalog.amexGold], in: context))
        XCTAssertTrue(only.choiceExplanation.contains("only card"))
        let bonus = Fixture.withWelcomeBonus(CardCatalog.citiDoubleCash, rewardUnits: 20_000, required: 100, deadline: Fixture.makeDate(2026, 9, 1))
        let boosted = try XCTUnwrap(engine.recommend(from: [CardCatalog.amexGold, bonus], in: context))
        XCTAssertEqual(boosted.best.card.id, bonus.id)
        XCTAssertTrue(boosted.choiceExplanation.contains("signup bonus"))
    }

    /// Today's panel prints the rate as a badge and the rationale as prose.
    /// If the rationale ever carries the rate again, that screen says "4x
    /// dining" twice, one line apart.
    func testRationaleLeavesTheRateToTheCaller() throws {
        let context = PurchaseContext(category: .dining, date: Fixture.inQ3)
        let engine = RecommendationEngine()
        let winner = try XCTUnwrap(engine.recommend(from: [CardCatalog.amexGold, CardCatalog.citiDoubleCash], in: context))
        XCTAssertFalse(winner.best.reason.isEmpty)
        XCTAssertFalse(winner.choiceRationale.contains(winner.best.reason))
        XCTAssertTrue(winner.choiceExplanation.hasPrefix(winner.choiceRationale))
        XCTAssertTrue(winner.choiceExplanation.contains(winner.best.reason))
    }

    func testMonthlyProgressOnlyCountsConfirmedEstimatesInThisMonth() throws {
        let now = Fixture.inQ3
        let context = PurchaseContext(category: .dining, date: now)
        let recommendation = try XCTUnwrap(RecommendationEngine().recommend(from: [CardCatalog.amexGold, CardCatalog.citiDoubleCash], in: context))
        let snapshot = RecommendationSnapshot(recommendation, context: context)
        let estimate = try XCTUnwrap(BenefitValueCalculator.estimate(for: snapshot, purchaseDollars: 100))
        var unconfirmed = estimate
        unconfirmed.isUserConfirmed = false
        let ledger = ImpactLedger(events: [
            ImpactEvent(kind: .estimatedBenefitCalculated, date: now, estimate: estimate),
            ImpactEvent(kind: .estimatedBenefitCalculated, date: Fixture.makeDate(2026, 7, 31), estimate: estimate),
            ImpactEvent(kind: .estimatedBenefitCalculated, date: now.addingTimeInterval(60), estimate: estimate),
            ImpactEvent(kind: .estimatedBenefitCalculated, date: now, estimate: unconfirmed),
            ImpactEvent(kind: .recommendationShown, date: now)
        ])
        let summary = EverydayInsights.monthlyImpact(ledger, asOf: now)
        XCTAssertEqual(summary.priced, 1)
        XCTAssertEqual(summary.estimatedIncrementalValueCents, estimate.incrementalValueCents ?? 0)
    }
}
