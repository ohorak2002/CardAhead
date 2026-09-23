import XCTest
@testable import CardKit

final class RecommendationEngineTests: XCTestCase {

    let engine = RecommendationEngine()

    private func context(
        _ category: SpendingCategory,
        merchant: String? = nil,
        confidence: MerchantConfidence = .exact,
        traveling: Bool = false,
        abroad: Bool = false,
        on date: Date = Fixture.inQ3
    ) -> PurchaseContext {
        PurchaseContext(
            category: category,
            merchantName: merchant,
            confidence: confidence,
            isTraveling: traveling,
            isAbroad: abroad,
            date: date
        )
    }

    // MARK: - Rate ranking

    func testHighestCategoryRateWins() {
        let wallet = [
            CardCatalog.citiDoubleCash,
            CardCatalog.capitalOneSavor,
            CardCatalog.amexGold
        ]
        let best = engine.rank(wallet, in: context(.dining)).first
        XCTAssertEqual(best?.card.displayName, "Amex Gold")
        XCTAssertEqual(best?.appliedRate, 4)
        XCTAssertEqual(best?.effectiveCentsPerDollar ?? 0, 4.0, accuracy: 0.0001)
    }

    func testFlatRateCardWinsWhenNoBonusApplies() {
        let wallet = [
            CardCatalog.amexGold,
            CardCatalog.citiDoubleCash,
            CardCatalog.chaseFreedomFlex
        ]
        // Home improvement is a bonus category on none of these.
        let best = engine.rank(wallet, in: context(.homeImprovement)).first
        XCTAssertEqual(best?.card.displayName, "Citi Double Cash")
        XCTAssertEqual(best?.reason, "2% on everything")
    }

    /// The point valuation is user-editable, and it has to be able to flip the answer.
    func testLowerPointValuationChangesTheWinner() {
        let devaluedGold = Fixture.valuing(CardCatalog.amexGold, centsPerUnit: 0.6)
        let wallet = [devaluedGold, CardCatalog.capitalOneSavor]

        let best = engine.rank(wallet, in: context(.dining)).first
        // 4x at 0.6 cents is 2.4 cents per dollar, less than Savor's flat 3%.
        XCTAssertEqual(best?.card.displayName, "Capital One Savor")
    }

    // MARK: - Caps

    func testExhaustedCapFallsBackToTheBaseRate() {
        let spentOut = Fixture.exhaustingCap(CardCatalog.amexBlueCashPreferred, category: .groceries)
        let score = engine.score(spentOut, in: context(.groceries))

        XCTAssertTrue(score.isCapExhausted)
        XCTAssertEqual(score.appliedRate, 1)
        XCTAssertTrue(score.caveats.contains { $0.contains("used up") })
    }

    func testExhaustedCapLosesToALowerUncappedRate() {
        let spentOut = Fixture.exhaustingCap(CardCatalog.amexBlueCashPreferred, category: .groceries)
        let wallet = [spentOut, CardCatalog.capitalOneSavor]

        let best = engine.rank(wallet, in: context(.groceries)).first
        XCTAssertEqual(best?.card.displayName, "Capital One Savor")
    }

    func testCapWithRoomLeftStillEarnsTheBonus() {
        var card = CardCatalog.amexBlueCashPreferred
        if let index = card.rules.firstIndex(where: { $0.category == .groceries }) {
            card.rules[index].cap?.spentDollars = 5_999
        }
        let score = engine.score(card, in: context(.groceries))
        XCTAssertFalse(score.isCapExhausted)
        XCTAssertEqual(score.appliedRate, 6)
    }

    // MARK: - Rotating categories

    func testUnactivatedRotatingBonusDoesNotEarn() {
        // Chase's real Q3 2026 rotation is gas and EV charging, public transit
        // and live entertainment.
        let flex = CardCatalog.chaseFreedomFlex
        let score = engine.score(flex, in: context(.gas))

        XCTAssertTrue(score.isRotatingMatch)
        XCTAssertTrue(score.needsActivation)
        XCTAssertEqual(score.appliedRate, 1, "An unactivated rotating bonus must not be credited")
    }

    func testActivatedRotatingBonusEarns() {
        let flex = Fixture.activatingRotation(CardCatalog.chaseFreedomFlex, quarter: Fixture.q3)
        let score = engine.score(flex, in: context(.gas))

        XCTAssertTrue(score.isRotatingMatch)
        XCTAssertFalse(score.needsActivation)
        XCTAssertEqual(score.appliedRate, 5)
    }

    func testActivatedRotatingBonusRespectsItsCap() {
        var flex = Fixture.activatingRotation(CardCatalog.chaseFreedomFlex, quarter: Fixture.q3)
        flex = Fixture.exhaustingRotatingCap(flex)

        let score = engine.score(flex, in: context(.gas))
        XCTAssertTrue(score.isCapExhausted)
        XCTAssertEqual(score.appliedRate, 1)
    }

    /// A quarter nobody has published is left out of the ranking, and said so
    /// rather than passed over in silence — it is a 5% bonus going unmentioned.
    func testAnUnpublishedQuarterIsLeftOutLoudly() {
        let flex = CardCatalog.chaseFreedomFlex
        let inQ4 = engine.score(flex, in: context(.dining, on: Fixture.makeDate(2026, 11, 10)))

        XCTAssertFalse(inQ4.isRotatingMatch)
        XCTAssertEqual(inQ4.appliedRate, 3, "the permanent dining rule still applies")
        XCTAssertTrue(
            inQ4.caveats.contains { $0.contains("CardWise has not verified") },
            "\(inQ4.caveats)"
        )
    }

    /// Discover publishes a year ahead, so its Q4 is known and gets no such note.
    func testAPublishedQuarterSaysNothingAboutBeingUnpublished() {
        let discover = CardCatalog.discoverIt
        let inQ4 = engine.score(discover, in: context(.dining, on: Fixture.makeDate(2026, 11, 10)))

        XCTAssertFalse(inQ4.isRotatingMatch)
        XCTAssertTrue(inQ4.caveats.contains { $0.contains("CardWise has not verified") }, "\(inQ4.caveats)")
    }

    /// The differentiator in the product spec: tell the user they forgot to click activate.
    func testActivationNudgeAppearsWhenTheBonusWouldHaveWon() {
        let wallet = [CardCatalog.chaseFreedomFlex, CardCatalog.capitalOneSavor]
        let recommendation = engine.recommend(from: wallet, in: context(.transit))

        XCTAssertEqual(recommendation?.best.card.displayName, "Capital One Savor")
        XCTAssertNotNil(recommendation?.activationNudge)
        XCTAssertEqual(recommendation?.activationNudge?.cardName, "Chase Freedom Flex")
        XCTAssertTrue(recommendation?.activationNudge?.sentence.contains("Chase Freedom Flex") ?? false)
        XCTAssertTrue(recommendation?.activationNudge?.shortSentence.contains("Chase Freedom Flex") ?? false)
    }

    func testNoActivationNudgeWhenTheBonusWouldNotHaveWon() {
        // Freedom Flex Q3 rotation does not cover dining, so nothing is being missed.
        let wallet = [CardCatalog.chaseFreedomFlex, CardCatalog.amexGold]
        let recommendation = engine.recommend(from: wallet, in: context(.dining))

        XCTAssertEqual(recommendation?.best.card.displayName, "Amex Gold")
        XCTAssertNil(recommendation?.activationNudge)
    }

    // MARK: - Welcome bonus

    func testOpenWelcomeBonusOutranksACategoryBonus() {
        // $600 of value with $3,000 left to spend is 20 cents per dollar.
        let withBonus = Fixture.withWelcomeBonus(
            CardCatalog.citiDoubleCash,
            rewardUnits: 60_000,
            required: 3_000
        )
        let wallet = [withBonus, CardCatalog.amexGold]

        let best = engine.rank(wallet, in: context(.dining)).first
        XCTAssertEqual(best?.card.displayName, "Citi Double Cash")
        XCTAssertEqual(best?.welcomeBonusBoostCentsPerDollar ?? 0, 20.0, accuracy: 0.0001)
        XCTAssertEqual(best?.total ?? 0, 22.0, accuracy: 0.0001)
    }

    func testMetWelcomeBonusStopsBoosting() {
        let met = Fixture.withWelcomeBonus(
            CardCatalog.citiDoubleCash,
            rewardUnits: 60_000,
            required: 3_000,
            spent: 3_000
        )
        let score = engine.score(met, in: context(.dining))
        XCTAssertEqual(score.welcomeBonusBoostCentsPerDollar, 0)
    }

    func testExpiredWelcomeBonusStopsBoosting() {
        let expired = Fixture.withWelcomeBonus(
            CardCatalog.citiDoubleCash,
            rewardUnits: 60_000,
            required: 3_000,
            deadline: Fixture.makeDate(2026, 1, 1)
        )
        let score = engine.score(expired, in: context(.dining))
        XCTAssertEqual(score.welcomeBonusBoostCentsPerDollar, 0)
    }

    /// A bonus with a dollar of spend left would otherwise score in the thousands.
    func testWelcomeBonusBoostIsCapped() {
        let nearlyDone = Fixture.withWelcomeBonus(
            CardCatalog.citiDoubleCash,
            rewardUnits: 60_000,
            required: 3_000,
            spent: 2_999
        )
        let score = engine.score(nearlyDone, in: context(.dining))
        XCTAssertEqual(score.welcomeBonusBoostCentsPerDollar, engine.maxWelcomeBonusBoostCentsPerDollar)
    }

    // MARK: - Travel

    func testForeignTransactionFeeIsSubtractedAbroad() {
        let wallet = [CardCatalog.chaseFreedomFlex, CardCatalog.chaseSapphirePreferred]

        let atHome = engine.rank(wallet, in: context(.dining)).first
        XCTAssertEqual(atHome?.card.displayName, "Chase Freedom Flex", "Tied on rate, lower annual fee wins")

        let abroad = engine.rank(wallet, in: context(.dining, abroad: true)).first
        XCTAssertEqual(abroad?.card.displayName, "Chase Sapphire Preferred")
        XCTAssertEqual(abroad?.effectiveCentsPerDollar ?? 0, 3.0, accuracy: 0.0001)
    }

    func testForeignTransactionFeeIsCalledOutInCaveats() {
        let score = engine.score(CardCatalog.chaseFreedomFlex, in: context(.dining, abroad: true))
        XCTAssertEqual(score.effectiveCentsPerDollar, 0.0, accuracy: 0.0001)
        XCTAssertTrue(score.caveats.contains { $0.contains("foreign transaction fee") })
    }

    func testTravelPerkSummaryOnlyAppearsWhileTraveling() {
        let wallet = [CardCatalog.chaseSapphirePreferred]

        let home = engine.recommend(from: wallet, in: context(.hotels))
        XCTAssertNil(home?.travelPerkSummary)

        let away = engine.recommend(from: wallet, in: context(.hotels, traveling: true))
        XCTAssertNotNil(away?.travelPerkSummary)
    }

    func testTravelPerksBreakATieWhileTraveling() {
        // Both flat 2% on a category neither bonuses, but only one carries travel cover.
        var plain = CardCatalog.wellsFargoActiveCash
        plain.perks = []
        var covered = CardCatalog.citiDoubleCash
        covered.perks = [.tripDelayInsurance, .rentalCarCDW]

        let best = engine.rank([plain, covered], in: context(.homeImprovement, traveling: true)).first
        XCTAssertEqual(best?.card.displayName, "Citi Double Cash")
    }

    // MARK: - Tiebreaks

    func testPinnedCardBreaksATie() {
        let pinned = Fixture.pinning(CardCatalog.wellsFargoActiveCash)
        let wallet = [CardCatalog.citiDoubleCash, pinned]

        let best = engine.rank(wallet, in: context(.homeImprovement)).first
        XCTAssertEqual(best?.card.displayName, "Wells Fargo Active Cash")
    }

    func testRankingIsStableRegardlessOfInputOrder() {
        let wallet = CardCatalog.all
        let forward = engine.rank(wallet, in: context(.dining)).map(\.card.displayName)
        let backward = engine.rank(Array(wallet.reversed()), in: context(.dining)).map(\.card.displayName)
        XCTAssertEqual(forward, backward)
    }

    // MARK: - Copy

    func testExactConfidenceNamesTheMerchant() {
        let recommendation = engine.recommend(
            from: [CardCatalog.amexGold],
            in: context(.dining, merchant: "ABC Restaurant")
        )
        XCTAssertEqual(recommendation?.headline, "ABC Restaurant 🍽️")
        XCTAssertEqual(recommendation?.detail, "Use Amex Gold here for 4x at restaurants!")
    }

    /// The two lines must not both spend themselves on the same fact. The
    /// title says where; the body says which card. Neither repeats the other.
    func testTheTitleAndBodySayDifferentThings() throws {
        let recommendation = try XCTUnwrap(engine.recommend(
            from: [CardCatalog.amexGold],
            in: context(.dining, merchant: "ABC Restaurant")
        ))
        XCTAssertFalse(recommendation.headline.contains("Amex Gold"), recommendation.headline)
        XCTAssertFalse(recommendation.detail.contains("ABC Restaurant"), recommendation.detail)
    }

    /// A title iOS truncates has thrown away the end of itself, and the end
    /// is where the meaning was. Roughly forty characters is what a lock
    /// screen shows before the ellipsis.
    func testEveryTitleFitsOnALockScreen() {
        for category in SpendingCategory.allCases {
            let recommendation = engine.recommend(
                from: [CardCatalog.citiDoubleCash],
                in: context(category, confidence: .categoryOnly)
            )
            let headline = recommendation?.headline ?? ""
            XCTAssertLessThanOrEqual(headline.count, 40, headline)
            XCTAssertTrue(headline.hasSuffix(category.emoji), headline)
        }
    }

    /// Indoor GPS cannot resolve one unit in a mall, so never name the wrong business.
    func testLowConfidenceFallsBackToTheCategory() {
        let recommendation = engine.recommend(
            from: [CardCatalog.amexGold],
            in: context(.dining, merchant: "ABC Restaurant", confidence: .categoryOnly)
        )
        XCTAssertEqual(recommendation?.headline, "Restaurant nearby 🍽️")
        XCTAssertEqual(recommendation?.detail, "Use Amex Gold for 4x at restaurants!")
        XCTAssertFalse(recommendation?.headline.contains("ABC Restaurant") ?? true)
    }

    func testCashBackReadsAsPercentAndPointsAsMultiplier() {
        let cash = engine.score(CardCatalog.capitalOneSavor, in: context(.dining))
        XCTAssertEqual(cash.reason, "3% dining")

        let points = engine.score(CardCatalog.amexGold, in: context(.dining))
        XCTAssertEqual(points.reason, "4x dining")
    }

    // MARK: - Structure

    func testEmptyWalletProducesNoRecommendation() {
        XCTAssertNil(engine.recommend(from: [], in: context(.dining)))
    }

    func testAlternatesHoldEveryOtherCard() {
        let wallet = CardCatalog.all
        let recommendation = engine.recommend(from: wallet, in: context(.dining))
        XCTAssertEqual(recommendation?.alternates.count, wallet.count - 1)
        XCTAssertFalse(recommendation?.alternates.contains { $0.id == recommendation?.best.id } ?? true)
    }

    func testWarehouseClubCaveatSurfaces() {
        let score = engine.score(CardCatalog.amexBlueCashPreferred, in: context(.warehouseClub))
        XCTAssertTrue(score.caveats.contains { $0.contains("do not code as supermarkets") })
    }
}
