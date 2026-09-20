import XCTest
@testable import CardKit

final class UpgradeTests: XCTestCase {
    private let date = CardCatalog.date(2026, 9, 20)
    private func offer() -> PersonalOffer {
        var offer = PersonalOffer(); offer.title = "Coffee offer"; offer.merchantNames = ["Acme Coffee"]
        offer.value = 10; offer.stacking = .addsToStandard
        return offer
    }
    private func context(_ name: String = "Acme Coffee", amount: Decimal? = 50) -> PurchaseContext {
        PurchaseContext(category: .dining, merchantName: name, date: date, purchaseDollars: amount, channel: .inStore)
    }
    func testAllNoneCustomAndRoundTrip() throws {
        var filter = MapFilter(); XCTAssertTrue(filter.isShowingEverything)
        filter.toggleAll(); XCTAssertTrue(filter.isShowingNothing); XCTAssertTrue(filter.categories.isEmpty)
        XCTAssertTrue(filter.effectiveCategories.isEmpty)
        filter.toggle(.restaurants); XCTAssertEqual(filter.categories, [.restaurants])
        filter.toggle(.hotels); XCTAssertEqual(filter.categories, [.restaurants, .hotels])
        filter.toggleAll(); XCTAssertTrue(filter.categories.isEmpty); XCTAssertTrue(filter.isShowingEverything)
        filter.toggle(.hotels); XCTAssertEqual(filter.categories, [.hotels])
        filter.toggle(.hotels); XCTAssertTrue(filter.isShowingNothing)
        let decoded = try JSONDecoder().decode(MapFilter.self, from: JSONEncoder().encode(filter))
        XCTAssertTrue(decoded.isShowingNothing)
    }
    func testOldEmptyFilterMigratesToAll() throws {
        let data = Data(#"{"categories":[],"distance":"threeMiles","sort":"nearest"}"#.utf8)
        XCTAssertTrue(try JSONDecoder().decode(MapFilter.self, from: data).isShowingEverything)
    }
    func testStaleSearchCannotPublishAfterNoneOrNewSearch() {
        var gate = PlaceRequestGate(); let old = gate.invalidate(); let latest = gate.invalidate()
        XCTAssertFalse(gate.accepts(old)); XCTAssertTrue(gate.accepts(latest))
        gate.invalidate(); XCTAssertFalse(gate.accepts(latest))
    }
    func testMerchantOfferNeverMatchesOtherRestaurantsOrSimilarNames() {
        XCTAssertNotNil(OfferEvaluator.evaluate(offer(), in: context(), centsPerPoint: 1))
        XCTAssertNil(OfferEvaluator.evaluate(offer(), in: context("Acme Coffee Roasters"), centsPerPoint: 1))
        XCTAssertNil(OfferEvaluator.evaluate(offer(), in: context("Another Cafe"), centsPerPoint: 1))
        var unknown = context(); unknown.confidence = .categoryOnly
        XCTAssertNil(OfferEvaluator.evaluate(offer(), in: unknown, centsPerPoint: 1))
    }
    func testDatesEnrollmentChannelUnknownAmountAndStackingStayConditional() throws {
        var offer = offer(); offer.enrollmentRequired = true
        XCTAssertNil(try XCTUnwrap(OfferEvaluator.evaluate(offer, in: context(), centsPerPoint: 1)).centsPerDollar)
        offer.enrolled = true; offer.channel = .online
        XCTAssertNil(try XCTUnwrap(OfferEvaluator.evaluate(offer, in: context(), centsPerPoint: 1)).centsPerDollar)
        offer.channel = .both; offer.stacking = .unknown
        XCTAssertNil(try XCTUnwrap(OfferEvaluator.evaluate(offer, in: context(), centsPerPoint: 1)).centsPerDollar)
        offer.stacking = .addsToStandard
        XCTAssertNil(try XCTUnwrap(OfferEvaluator.evaluate(offer, in: context(amount: nil), centsPerPoint: 1)).centsPerDollar)
        offer.startsOn = date.addingTimeInterval(1)
        XCTAssertNil(OfferEvaluator.evaluate(offer, in: context(), centsPerPoint: 1))
        offer.startsOn = nil; offer.expiresOn = date.addingTimeInterval(-1)
        XCTAssertNil(OfferEvaluator.evaluate(offer, in: context(), centsPerPoint: 1))
    }
    func testThresholdCapRemainingUsesAndDecimalRounding() throws {
        var offer = offer(); offer.reward = .spendGet; offer.minimumSpend = 50; offer.maximumReward = 7
        XCTAssertNil(try XCTUnwrap(OfferEvaluator.evaluate(offer, in: context(amount: 49), centsPerPoint: 1)).centsPerDollar)
        XCTAssertEqual(OfferEvaluator.evaluate(offer, in: context(), centsPerPoint: 1)?.estimatedRewardDollars, 7)
        offer.redemptions = [OfferRedemption(date: date, purchaseDollars: 50, receivedDollars: 7)]
        XCTAssertNil(OfferEvaluator.evaluate(offer, in: context(), centsPerPoint: 1))
        offer = self.offer(); offer.spendingCap = 25
        XCTAssertEqual(OfferEvaluator.evaluate(offer, in: context(), centsPerPoint: 1)?.estimatedRewardDollars, Decimal(string: "2.50"))
        offer.spendingCap = nil; offer.value = 3
        XCTAssertEqual(OfferEvaluator.evaluate(offer, in: context(amount: Decimal(string: "10.99")), centsPerPoint: 1)?.estimatedRewardDollars, Decimal(string: "0.33"))
    }
    func testRecurringUsageResetsAndOffersDoNotStackTogether() {
        var first = offer(); first.recurrence = .monthly
        first.redemptions = [OfferRedemption(date: CardCatalog.date(2026, 8, 20), purchaseDollars: 50, receivedDollars: 5)]
        XCTAssertNotNil(OfferEvaluator.evaluate(first, in: context(), centsPerPoint: 1)?.centsPerDollar)
        var card = Card(issuer: "Test", name: "Cash", rules: [CategoryRule(category: .base, rate: 2)])
        var second = first; second.id = UUID(); second.value = 5
        card.personalOffers = [first, second]
        let engine = RecommendationEngine()
        XCTAssertEqual(engine.score(card, in: context()).effectiveCentsPerDollar, 12)
        second.stacking = .replacesStandard; second.value = 20; card.personalOffers = [second]
        XCTAssertEqual(engine.score(card, in: context()).effectiveCentsPerDollar, 20)
    }
    func testPersonalEditsPreserveProductAndCatalogAndRestoreIndividually() throws {
        var card = CardCatalog.amexGold
        let standard = card.rule(for: .dining)!.rate
        card.rules[card.rules.firstIndex { $0.category == .dining }!].rate = 7
        XCTAssertTrue(card.isUserAdjusted(.rule(.dining)))
        XCTAssertFalse(card.isUserAdjusted(.rule(.groceries)))
        XCTAssertEqual(CardCatalog.amexGold.rule(for: .dining)?.rate, standard)
        XCTAssertNil(card.benefits().first { $0.id == "rule.dining" }?.verifiedOn)
        card.personalOffers = [offer()]
        card.reviewCatalogUpdate(); XCTAssertEqual(card.rule(for: .dining)?.rate, 7)
        card.restoreBenefit(.rule(.dining)); XCTAssertEqual(card.rule(for: .dining)?.rate, standard)
        XCTAssertEqual(card.personalOffers?.count, 1); XCTAssertEqual(card.catalogProductID, "amex-gold")
        let benefit = try XCTUnwrap(card.benefits().first { $0.id == "rule.groceries" })
        card = card.removingBenefit(benefit); card.reviewCatalogUpdate()
        XCTAssertNil(card.rule(for: .groceries))
        card.restoreBenefit(.rule(.groceries)); XCTAssertNotNil(card.rule(for: .groceries))
    }
    func testLegacyWalletMigrationPreservesDataWithoutFalseVerification() throws {
        var card = CardCatalog.amexGold; card.photoFilename = "user.jpg"; card.catalogBaseline = nil
        let roundTrip = try JSONDecoder().decode(Card.self, from: JSONEncoder().encode(card))
        XCTAssertEqual(roundTrip.rules, card.rules); XCTAssertEqual(roundTrip.photoFilename, "user.jpg")
        XCTAssertEqual(roundTrip.catalogProductID, "amex-gold"); XCTAssertTrue(roundTrip.isUserAdjusted(.rule(.dining)))
    }
    func testCatalogRestrictionsAndUnverifiedBenefits() {
        let engine = RecommendationEngine()
        XCTAssertEqual(engine.score(CardCatalog.costcoAnywhereVisa, in: PurchaseContext(category: .warehouseClub, merchantName: "Sam's Club")).appliedRate, 1)
        XCTAssertEqual(engine.score(CardCatalog.costcoAnywhereVisa, in: PurchaseContext(category: .warehouseClub, merchantName: "Costco")).appliedRate, 2)
        XCTAssertEqual(engine.score(CardCatalog.amexGold, in: PurchaseContext(category: .travelPortal)).appliedRate, 1)
        XCTAssertTrue(CardCatalog.discoverIt.rotatingProgram!.quarters.isEmpty)
        XCTAssertFalse(CardCatalog.discoverIt.perks.contains(.firstYearCashbackMatch))
        XCTAssertNil(CardCatalog.capitalOneSavor.benefits().first?.verifiedOn)
    }
    func testCapCrossingAndFrozenHistory() throws {
        var card = CardCatalog.amexBlueCashPreferred
        let i = card.rules.firstIndex { $0.category == .groceries }!
        card.rules[i].cap?.spentDollars = 5990
        let ctx = PurchaseContext(category: .groceries, date: date)
        let recommendation = try XCTUnwrap(RecommendationEngine().recommend(from: [card, CardCatalog.citiDoubleCash], in: ctx))
        let snapshot = RecommendationSnapshot(recommendation, context: ctx)
        card.rules[i].rate = 10
        let estimate = try XCTUnwrap(BenefitValueCalculator.estimate(for: snapshot, purchaseDollars: 100))
        XCTAssertEqual(estimate.estimatedValueCents, 150, accuracy: 0.001)
        XCTAssertEqual(estimate.incrementalValueCents!, -50, accuracy: 0.001)
        let restored = try JSONDecoder().decode(RecommendationSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(restored.capRemainingDollars, 10)
    }
    func testConsentRetriesDeduplicationDisableAndDeletion() throws {
        let event = ImpactEvent(kind: .recommendationAccepted, date: date, recommendationID: UUID())
        let record = try XCTUnwrap(SharedImpactRecord(event: event))
        var state = ImpactSharingState()
        state.enqueue(record, createdAt: date); XCTAssertTrue(state.pending.isEmpty)
        state.enable(at: date)
        state.enqueue(record, createdAt: date.addingTimeInterval(-1)); XCTAssertTrue(state.pending.isEmpty)
        state.enqueue(record, createdAt: date); state.enqueue(record, createdAt: date)
        XCTAssertEqual(state.pending.count, 1)
        let epoch = state.epoch; state.failed(at: date)
        XCTAssertEqual(state.pending.first?.id, record.id); XCTAssertNotNil(state.retryAfter)
        state.disable(deletePreviouslyShared: true); XCTAssertTrue(state.pending.isEmpty)
        state.acknowledge([record.id], epoch: epoch); XCTAssertTrue(state.needsDeletion)
        state.enable(); XCTAssertFalse(state.enabled)
        state.acknowledgePrivacyChange(); state.enable(); XCTAssertTrue(state.enabled)
        let decoded = try JSONDecoder().decode(ImpactSharingState.self, from: JSONEncoder().encode(state))
        XCTAssertTrue(decoded.enabled)
    }
    func testExportContainsNoLocalIdentifiersOrNames() throws {
        let redemption = OfferRedemption(purchaseDollars: 100, receivedDollars: 10)
        let record = SharedImpactRecord(redemption: redemption, productID: "Custom private card name", category: .dining)
        let json = String(data: try JSONEncoder().encode(record), encoding: .utf8)!
        XCTAssertFalse(json.contains("Custom private")); XCTAssertFalse(json.contains("purchase_cents"))
        XCTAssertFalse(json.contains("merchant")); XCTAssertFalse(json.contains("cardID"))
    }
}
