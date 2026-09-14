import XCTest
@testable import CardKit

/// What a recommendation was worth, and — the part that matters — what
/// *choosing* it was worth over the next best card in the same wallet.
final class BenefitEstimateTests: XCTestCase {

    private let engine = RecommendationEngine()
    private let now = Fixture.inQ3

    private func diningContext(date: Date? = nil) -> PurchaseContext {
        PurchaseContext(
            category: .dining,
            merchantName: "XYZ Restaurant",
            confidence: .exact,
            date: date ?? now
        )
    }

    private func snapshot(
        cards: [Card],
        context: PurchaseContext? = nil
    ) throws -> RecommendationSnapshot {
        let context = context ?? diningContext()
        let recommendation = try XCTUnwrap(engine.recommend(from: cards, in: context))
        return RecommendationSnapshot(recommendation, context: context)
    }

    // MARK: - The arithmetic

    /// The example the product is built around: 4x dining against a 2% card,
    /// on an $85 dinner.
    func testFourTimesDiningOnEightyFiveDollars() throws {
        let snapshot = try snapshot(cards: [CardCatalog.amexGold, CardCatalog.citiDoubleCash])
        let estimate = try XCTUnwrap(BenefitValueCalculator.estimate(for: snapshot, purchaseDollars: 85))

        XCTAssertEqual(estimate.cardName, "Amex Gold")
        XCTAssertEqual(estimate.appliedRate, 4, accuracy: 0.0001)
        XCTAssertEqual(estimate.rewardUnits, 340, accuracy: 0.0001)
        XCTAssertEqual(estimate.estimatedValueCents, 340, accuracy: 0.0001)
    }

    /// The number the app is allowed to claim credit for. Any card would have
    /// earned something; only the difference came from being told which one.
    func testIncrementalValueIsMeasuredAgainstTheBestOtherCard() throws {
        let snapshot = try snapshot(cards: [CardCatalog.amexGold, CardCatalog.citiDoubleCash])
        let estimate = try XCTUnwrap(BenefitValueCalculator.estimate(for: snapshot, purchaseDollars: 85))

        XCTAssertEqual(estimate.comparedWithCardName, "Citi Double Cash")
        XCTAssertEqual(estimate.comparedWithValueCents ?? 0, 170, accuracy: 0.0001)
        XCTAssertEqual(estimate.incrementalValueCents ?? 0, 170, accuracy: 0.0001)
    }

    /// One card is not a choice, so nothing is attributable to having made one.
    func testAWalletWithOneCardHasNoIncrementalValue() throws {
        let snapshot = try snapshot(cards: [CardCatalog.amexGold])
        let estimate = try XCTUnwrap(BenefitValueCalculator.estimate(for: snapshot, purchaseDollars: 85))

        XCTAssertNil(estimate.comparedWithCardName)
        XCTAssertNil(estimate.incrementalValueCents)
        XCTAssertEqual(estimate.estimatedValueCents, 340, accuracy: 0.0001)
    }

    /// A point is worth whatever the user said it is worth in Settings, and
    /// the estimate has to move with them.
    func testTheUsersOwnPointValuationFlowsThrough() throws {
        let gold = Fixture.valuing(CardCatalog.amexGold, centsPerUnit: 2.0)
        let snapshot = try snapshot(cards: [gold, CardCatalog.citiDoubleCash])
        let estimate = try XCTUnwrap(BenefitValueCalculator.estimate(for: snapshot, purchaseDollars: 100))

        // 4 points a dollar, each worth two cents.
        XCTAssertEqual(estimate.rewardUnits, 400, accuracy: 0.0001)
        XCTAssertEqual(estimate.estimatedValueCents, 800, accuracy: 0.0001)
        XCTAssertEqual(estimate.incrementalValueCents ?? 0, 600, accuracy: 0.0001)
    }

    /// A fee abroad is real money off the top, and the engine has already
    /// taken it off before this ever sees it.
    func testAForeignTransactionFeeIsAlreadyOutOfTheRate() throws {
        let context = PurchaseContext(category: .base, confidence: .exact, isAbroad: true, date: now)
        let snapshot = try snapshot(cards: [CardCatalog.citiDoubleCash], context: context)
        let estimate = try XCTUnwrap(BenefitValueCalculator.estimate(for: snapshot, purchaseDollars: 100))

        // 2% earned, 3% lost to the fee.
        XCTAssertEqual(estimate.estimatedValueCents, -100, accuracy: 0.0001)
    }

    func testAPurchaseOfNothingIsNotAnEstimate() throws {
        let snapshot = try snapshot(cards: [CardCatalog.amexGold, CardCatalog.citiDoubleCash])
        XCTAssertNil(BenefitValueCalculator.estimate(for: snapshot, purchaseDollars: 0))
        XCTAssertNil(BenefitValueCalculator.estimate(for: snapshot, purchaseDollars: -20))
    }

    // MARK: - Which card counts as the alternative

    /// The ranking can be won by a signup bonus — a projection spread over
    /// spend nobody has done yet. Measuring this purchase against a projection
    /// would credit the app with money that does not exist, so the comparison
    /// is against what the other card pays *here*.
    func testTheAlternativeIsTheBestEarnerHereNotTheRankingRunnerUp() throws {
        // A 1% card with a big open bonus outranks a 2% card, but earns less
        // at this till.
        let bonusCard = Fixture.withWelcomeBonus(
            CardCatalog.wellsFargoActiveCash,
            rewardUnits: 20_000,
            required: 1_000,
            deadline: Fixture.makeDate(2026, 12, 31)
        )
        let context = PurchaseContext(category: .dining, confidence: .exact, date: now)
        let snapshot = try snapshot(cards: [bonusCard, CardCatalog.amexGold], context: context)

        XCTAssertEqual(snapshot.cardName, bonusCard.displayName)
        XCTAssertEqual(snapshot.alternateCardName, "Amex Gold")
        XCTAssertTrue(snapshot.wasChosenForWelcomeBonus)
    }

    /// And when that happens the estimate says so, in the negative, rather
    /// than quietly reporting a win.
    func testABonusDrivenChoiceReportsANegativeIncrementalValue() throws {
        let bonusCard = Fixture.withWelcomeBonus(
            CardCatalog.wellsFargoActiveCash,
            rewardUnits: 20_000,
            required: 1_000,
            deadline: Fixture.makeDate(2026, 12, 31)
        )
        let context = PurchaseContext(category: .dining, confidence: .exact, date: now)
        let snapshot = try snapshot(cards: [bonusCard, CardCatalog.amexGold], context: context)
        let estimate = try XCTUnwrap(BenefitValueCalculator.estimate(for: snapshot, purchaseDollars: 100))

        XCTAssertLessThan(estimate.incrementalValueCents ?? 0, 0)
        XCTAssertTrue(estimate.wasChosenForWelcomeBonus)
        let summary = try XCTUnwrap(estimate.incrementalSummary)
        XCTAssertTrue(summary.contains("signup bonus"), summary)
    }

    // MARK: - The words

    func testTheRewardSummaryNamesThePointsRatherThanImplyingCash() throws {
        let snapshot = try snapshot(cards: [CardCatalog.amexGold, CardCatalog.citiDoubleCash])
        let estimate = try XCTUnwrap(BenefitValueCalculator.estimate(for: snapshot, purchaseDollars: 85))
        XCTAssertTrue(estimate.rewardSummary.contains("Membership Rewards"), estimate.rewardSummary)
    }

    func testACashBackCardIsDescribedAsCashBack() throws {
        let context = PurchaseContext(category: .base, confidence: .exact, date: now)
        let snapshot = try snapshot(cards: [CardCatalog.citiDoubleCash], context: context)
        let estimate = try XCTUnwrap(BenefitValueCalculator.estimate(for: snapshot, purchaseDollars: 50))
        XCTAssertTrue(estimate.rewardSummary.contains("cash back"), estimate.rewardSummary)
    }

    /// Two cards paying the same thing here is not a win to brag about.
    func testAnEqualAlternativeIsDescribedAsAboutTheSame() throws {
        let twin = Card(
            issuer: "Other",
            name: "Bank Card",
            currency: .cashBack,
            rules: [CategoryRule(category: .base, rate: 2)]
        )
        let context = PurchaseContext(category: .base, confidence: .exact, date: now)
        let snapshot = try snapshot(cards: [CardCatalog.citiDoubleCash, twin], context: context)
        let estimate = try XCTUnwrap(BenefitValueCalculator.estimate(for: snapshot, purchaseDollars: 100))

        let summary = try XCTUnwrap(estimate.incrementalSummary)
        XCTAssertTrue(summary.contains("about the same"), summary)
    }

    /// The follow-up question has to be recognisable without naming where
    /// somebody was, because nothing in this ledger records where they were.
    func testTheFollowUpDescriptionNamesTheCardAndTheCategoryOnly() throws {
        let snapshot = try snapshot(cards: [CardCatalog.amexGold, CardCatalog.citiDoubleCash])
        XCTAssertEqual(snapshot.followUpDescription, "Amex Gold for dining")
        XCTAssertFalse(snapshot.followUpDescription.contains("XYZ"))
    }

    /// A snapshot is frozen at the moment of the suggestion, so the wallet
    /// moving on afterwards cannot rewrite what was said.
    func testASnapshotKeepsTheProductItCameFrom() throws {
        let snapshot = try snapshot(cards: [CardCatalog.amexGold, CardCatalog.citiDoubleCash])
        XCTAssertEqual(snapshot.cardProductID, "amex-gold")
        XCTAssertEqual(snapshot.category, .dining)
        XCTAssertEqual(snapshot.confidence, .exact)
    }
}
