import XCTest
@testable import CardKit

/// The Benefits screen's whole job is to be understandable, and its whole risk
/// is becoming a second description of the card that drifts from the one the
/// ranking engine reads. These tests hold both ends: the words stay plain, and
/// a correction lands in the structures the engine already uses.
final class CardBenefitTests: XCTestCase {

    private let today = Fixture.inQ3

    private func benefit(_ card: Card, id: String) -> CardBenefit? {
        card.benefits(asOf: today).first { $0.id == id }
    }

    // MARK: - Reading a card in plain English

    func testARateReadsTheWayAPersonWouldSayIt() throws {
        let gold = CardCatalog.amexGold
        let dining = try XCTUnwrap(benefit(gold, id: "rule.dining"))

        XCTAssertEqual(dining.title, "4x at restaurants")
        XCTAssertEqual(dining.detail, "Restaurants worldwide.")
        XCTAssertEqual(dining.group, .dining)
        XCTAssertEqual(dining.kind, .rewardRate)
        XCTAssertEqual(dining.relatedSpendingCategory, .dining)
    }

    func testCashBackSaysPercentAndPointsSayTimes() throws {
        let cash = try XCTUnwrap(benefit(CardCatalog.capitalOneSavor, id: "rule.dining"))
        let points = try XCTUnwrap(benefit(CardCatalog.chaseSapphirePreferred, id: "rule.dining"))
        XCTAssertEqual(cash.title, "3% at restaurants")
        XCTAssertEqual(points.title, "3x at restaurants")
    }

    func testEveryBenefitOnEveryCatalogCardHasSomethingToRead() {
        for card in CardCatalog.all {
            let benefits = card.benefits(asOf: today)
            XCTAssertFalse(benefits.isEmpty, card.displayName)
            for benefit in benefits {
                XCTAssertFalse(benefit.title.isEmpty, "\(card.displayName) has a benefit with no words on it")
                XCTAssertFalse(benefit.title.contains("CategoryRule"), card.displayName)
                XCTAssertNotEqual(benefit.detail, "", card.displayName)
            }
        }
    }

    func testBenefitsComeOutGroupedInReadingOrder() throws {
        let orders = CardCatalog.amexGold.benefits(asOf: today).map(\.group.sortOrder)
        XCTAssertEqual(orders, orders.sorted(), "the screen renders these in order and does not re-sort them")
        // The base rate is not the headline. It sits after everything the card
        // actually pays extra on.
        let groups = CardCatalog.amexGold.benefits(asOf: today).map(\.group)
        let dining = try XCTUnwrap(groups.firstIndex(of: .dining))
        let everythingElse = try XCTUnwrap(groups.firstIndex(of: .everydaySpending))
        XCTAssertLessThan(dining, everythingElse)
    }

    // MARK: - Where the numbers came from

    func testACatalogCardCarriesItsSourceDate() throws {
        let benefit = try XCTUnwrap(benefit(CardCatalog.amexGold, id: "rule.dining"))
        XCTAssertEqual(benefit.source, .catalog)
        XCTAssertEqual(benefit.verifiedOn, CardCatalog.checkedOn)
    }

    /// A card somebody typed in has no source and must not borrow one.
    func testACardDescribedByHandHasNoSourceDate() throws {
        let byHand = Card(
            issuer: "Local credit union",
            name: "Everyday",
            rules: [CategoryRule(category: .gas, rate: 2), CategoryRule(category: .base, rate: 1)]
        )
        let benefit = try XCTUnwrap(benefit(byHand, id: "rule.gas"))
        XCTAssertEqual(benefit.source, .user)
        XCTAssertNil(benefit.verifiedOn)
    }

    /// The catalog's most important single fact. Sapphire Preferred's grocery
    /// bonus is online-only, so it is not a rule — and it must not reappear as
    /// a benefit either, or the screen would promise it back.
    func testSapphirePreferredStillClaimsNoGroceryBenefit() {
        let benefits = CardCatalog.chaseSapphirePreferred.benefits(asOf: today)
        XCTAssertFalse(benefits.contains { $0.relatedSpendingCategory == .groceries })
    }

    // MARK: - What is actually paying right now

    func testACapUsedUpShowsAsNotPaying() throws {
        let spentOut = Fixture.exhaustingCap(CardCatalog.amexBlueCashPreferred, category: .groceries)
        let benefit = try XCTUnwrap(benefit(spentOut, id: "rule.groceries"))
        XCTAssertFalse(benefit.isActive)
        XCTAssertEqual(benefit.cap?.limitDollars, 6_000)
    }

    func testAnUnswitchedQuarterShowsAsNotPayingAndSaysWhy() throws {
        let flex = CardCatalog.chaseFreedomFlex
        let rotating = try XCTUnwrap(benefit(flex, id: "rotating"))

        XCTAssertEqual(rotating.group, .creditsAndBonuses)
        XCTAssertEqual(rotating.kind, .rotatingRate)
        XCTAssertFalse(rotating.isActive)
        XCTAssertEqual(rotating.detail?.contains("switch it on with the issuer"), true)

        let switchedOn = Fixture.activatingRotation(flex, quarter: Fixture.q3)
        XCTAssertEqual(CardBenefit.benefits(for: switchedOn, asOf: today).first { $0.id == "rotating" }?.isActive, true)
    }

    /// Past the edge of what anybody has published, the benefit still appears —
    /// it is a real feature of the card — but it says nobody knows yet rather
    /// than inventing a list.
    func testAnUnpublishedQuarterSaysSoRatherThanGuessing() throws {
        let inQ4 = Fixture.makeDate(2026, 11, 1)
        let rotating = try XCTUnwrap(
            CardBenefit.benefits(for: CardCatalog.chaseFreedomFlex, asOf: inQ4).first { $0.id == "rotating" }
        )
        XCTAssertEqual(rotating.detail, "Chase has not published this quarter's list yet.")
        XCTAssertFalse(rotating.isActive)
    }

    func testAnOpenSignupBonusIsABenefitAndAnExpiredOneIsNot() throws {
        let open = Fixture.withWelcomeBonus(
            CardCatalog.chaseSapphirePreferred,
            rewardUnits: 60_000,
            required: 4_000,
            deadline: Fixture.makeDate(2026, 12, 31)
        )
        let bonus = try XCTUnwrap(benefit(open, id: "welcomeBonus"))
        XCTAssertTrue(bonus.title.contains("60,000"))
        XCTAssertTrue(bonus.isActive)
        XCTAssertEqual(bonus.group, .creditsAndBonuses)

        let expired = Fixture.withWelcomeBonus(
            CardCatalog.chaseSapphirePreferred,
            rewardUnits: 60_000,
            required: 4_000,
            deadline: Fixture.makeDate(2026, 1, 1)
        )
        XCTAssertNil(benefit(expired, id: "welcomeBonus"))
    }

    /// A cash back unit is one cent, the same unit its "2%" is written in —
    /// see `WelcomeBonus.rewardUnits`. Printing the units straight out as
    /// dollars read "$20,000 back" for a $200 bonus.
    func testACashBackSignupBonusIsShownInDollarsNotInUnits() throws {
        let card = Fixture.withWelcomeBonus(
            CardCatalog.wellsFargoActiveCash,
            rewardUnits: 20_000,
            required: 1_000,
            deadline: Fixture.makeDate(2026, 12, 31)
        )
        let bonus = try XCTUnwrap(benefit(card, id: "welcomeBonus"))
        XCTAssertTrue(bonus.title.contains("$200"), bonus.title)
        XCTAssertFalse(bonus.title.contains("20,000"), bonus.title)
    }

    // MARK: - Perks land somewhere sensible

    func testATravelCreditIsMoneyAndSitsWithTheBonuses() throws {
        let credit = try XCTUnwrap(benefit(CardCatalog.chaseSapphirePreferred, id: "perk.annualTravelCredit"))
        XCTAssertEqual(credit.group, .creditsAndBonuses)
        XCTAssertEqual(credit.kind, .credit)

        let insurance = try XCTUnwrap(benefit(CardCatalog.chaseFreedomFlex, id: "perk.cellPhoneProtection"))
        XCTAssertEqual(insurance.group, .cardPerks)
        XCTAssertEqual(insurance.kind, .insurance)
    }

    // MARK: - Correcting a card

    /// The point of the whole model: a correction is written into the card the
    /// engine already reads, and touches nothing else on it.
    func testRemovingARateTouchesOnlyThatRule() throws {
        let gold = Fixture.pinning(CardCatalog.amexGold)
        let dining = try XCTUnwrap(benefit(gold, id: "rule.dining"))
        let corrected = gold.removingBenefit(dining)

        XCTAssertNil(corrected.rule(for: .dining))
        XCTAssertEqual(corrected.rule(for: .groceries)?.cap?.limitDollars, 25_000)
        XCTAssertEqual(corrected.perks, gold.perks)
        XCTAssertEqual(corrected.notes, gold.notes)
        XCTAssertEqual(corrected.annualFeeDollars, gold.annualFeeDollars)
        XCTAssertTrue(corrected.isPinned)
        XCTAssertEqual(corrected.id, gold.id)
        XCTAssertEqual(corrected.catalogProductID, "amex-gold")
    }

    func testRemovingAPerkLeavesEveryRateAlone() throws {
        let gold = CardCatalog.amexGold
        let perk = try XCTUnwrap(benefit(gold, id: "perk.noForeignTransactionFee"))
        let corrected = gold.removingBenefit(perk)

        XCTAssertFalse(corrected.perks.contains(.noForeignTransactionFee))
        XCTAssertEqual(corrected.rules, gold.rules)
    }

    /// Removing the base rate would leave a card that earns nothing at all, so
    /// the row does not offer it.
    func testTheBaseRateCannotBeRemoved() throws {
        let gold = CardCatalog.amexGold
        let base = try XCTUnwrap(benefit(gold, id: "rule.base"))
        XCTAssertFalse(base.isRemovable)
        XCTAssertEqual(gold.removingBenefit(base).rules, gold.rules)
    }

    /// The rotating programme belongs to the issuer. Hiding it here would only
    /// hide it from the person it is being kept honest for.
    func testTheRotatingQuarterCannotBeRemoved() throws {
        let flex = CardCatalog.chaseFreedomFlex
        let rotating = try XCTUnwrap(benefit(flex, id: "rotating"))
        XCTAssertFalse(rotating.isRemovable)
        XCTAssertNotNil(flex.removingBenefit(rotating).rotatingProgram)
    }

    func testRemovingSeveralBenefitsAtOnce() {
        let gold = CardCatalog.amexGold
        let corrected = gold.removingBenefits(
            ids: ["rule.dining", "perk.noForeignTransactionFee", "rule.base", "rotating"],
            asOf: today
        )

        XCTAssertNil(corrected.rule(for: .dining))
        XCTAssertFalse(corrected.perks.contains(.noForeignTransactionFee))
        // The base rate refuses, and "rotating" names nothing on this card.
        XCTAssertNotNil(corrected.rule(for: .base))
    }

    func testRemovingNothingChangesNothing() {
        let gold = CardCatalog.amexGold
        XCTAssertEqual(gold.removingBenefits(ids: [], asOf: today), gold)
    }

    // MARK: - Picking the wrong card

    /// Changing a card is a correction, not a fresh start. The slot, the star
    /// and the photo of the real card in your hand survive it; everything the
    /// catalog asserts comes from the card replacing it.
    func testChangingTheCardKeepsThePlaceAndLosesTheProduct() {
        var wrong = CardCatalog.chaseFreedomFlex
        wrong.isPinned = true
        wrong.photoFilename = "mine.jpg"

        let right = CardCatalog.amexGold.takingWalletPlace(of: wrong)

        XCTAssertEqual(right.id, wrong.id, "the wallet slot has to survive, or replace() cannot find it")
        XCTAssertTrue(right.isPinned)
        XCTAssertEqual(right.photoFilename, "mine.jpg")

        XCTAssertEqual(right.catalogProductID, "amex-gold")
        XCTAssertEqual(right.name, "Gold")
        XCTAssertEqual(right.annualFeeDollars, 325)
        XCTAssertNil(right.rotatingProgram, "the wrong card's quarterly bonus must not come along")
    }

    func testChangingToTheSameCardChangesNothingThatMatters() {
        let held = Fixture.pinning(CardCatalog.amexGold)
        let again = CardCatalog.amexGold.takingWalletPlace(of: held)
        XCTAssertEqual(again, held)
    }

    // MARK: - The engine stays in charge

    /// A corrected card is ranked on the correction, because the correction is
    /// in the card. If this ever needs a second code path, the model is wrong.
    func testACorrectedCardIsRankedOnTheCorrection() throws {
        let engine = RecommendationEngine()
        let gold = CardCatalog.amexGold
        let context = PurchaseContext(category: .dining, date: today)

        XCTAssertEqual(engine.score(gold, in: context).appliedRate, 4)

        let dining = try XCTUnwrap(benefit(gold, id: "rule.dining"))
        let corrected = gold.removingBenefit(dining)
        XCTAssertEqual(engine.score(corrected, in: context).appliedRate, gold.baseRate)
    }
}
