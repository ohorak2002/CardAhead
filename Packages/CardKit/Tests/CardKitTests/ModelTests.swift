import XCTest
@testable import CardKit

final class QuarterTests: XCTestCase {

    func testQuarterBoundaries() {
        let calendar = Calendar(identifier: .gregorian)
        XCTAssertEqual(Quarter.containing(Fixture.makeDate(2026, 1, 1), calendar: calendar).index, 1)
        XCTAssertEqual(Quarter.containing(Fixture.makeDate(2026, 3, 31), calendar: calendar).index, 1)
        XCTAssertEqual(Quarter.containing(Fixture.makeDate(2026, 4, 1), calendar: calendar).index, 2)
        XCTAssertEqual(Quarter.containing(Fixture.makeDate(2026, 6, 30), calendar: calendar).index, 2)
        XCTAssertEqual(Quarter.containing(Fixture.makeDate(2026, 7, 1), calendar: calendar).index, 3)
        XCTAssertEqual(Quarter.containing(Fixture.makeDate(2026, 9, 30), calendar: calendar).index, 3)
        XCTAssertEqual(Quarter.containing(Fixture.makeDate(2026, 10, 1), calendar: calendar).index, 4)
        XCTAssertEqual(Quarter.containing(Fixture.makeDate(2026, 12, 31), calendar: calendar).index, 4)
    }

    func testRawValueRoundTrips() {
        let quarter = Quarter(year: 2026, index: 3)
        XCTAssertEqual(quarter.rawValue, "2026-Q3")
        XCTAssertEqual(Quarter(rawValue: "2026-Q3"), quarter)
    }

    func testMalformedRawValuesAreRejected() {
        XCTAssertNil(Quarter(rawValue: "2026Q3"))
        XCTAssertNil(Quarter(rawValue: "2026-Q5"))
        XCTAssertNil(Quarter(rawValue: "twenty-Q3"))
        XCTAssertNil(Quarter(rawValue: ""))
    }

    func testOrdering() {
        XCTAssertLessThan(Quarter(year: 2026, index: 4), Quarter(year: 2027, index: 1))
        XCTAssertLessThan(Quarter(year: 2026, index: 1), Quarter(year: 2026, index: 2))
    }

    func testCodableUsesTheCompactForm() throws {
        let data = try JSONEncoder().encode(Quarter(year: 2026, index: 3))
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"2026-Q3\"")
        XCTAssertEqual(try JSONDecoder().decode(Quarter.self, from: data), Quarter(year: 2026, index: 3))
    }
}

final class EarnCapTests: XCTestCase {

    func testRemainingNeverGoesNegative() {
        let cap = EarnCap(limitDollars: 1_500, period: .quarterly, spentDollars: 2_000)
        XCTAssertEqual(cap.remainingDollars, 0)
        XCTAssertTrue(cap.isExhausted)
        XCTAssertEqual(cap.fractionUsed, 1.0, accuracy: 0.0001)
    }

    func testFractionUsed() {
        let cap = EarnCap(limitDollars: 1_000, period: .quarterly, spentDollars: 250)
        XCTAssertEqual(cap.fractionUsed, 0.25, accuracy: 0.0001)
        XCTAssertFalse(cap.isExhausted)
    }

    func testResetClearsSpend() {
        let cap = EarnCap(limitDollars: 1_500, period: .quarterly, spentDollars: 1_500)
        XCTAssertEqual(cap.resetForNewPeriod().spentDollars, 0)
    }
}

final class WelcomeBonusTests: XCTestCase {

    func testOpenBonus() {
        let bonus = WelcomeBonus(
            rewardUnits: 60_000,
            requiredSpendDollars: 4_000,
            spentDollars: 1_000,
            deadline: Fixture.makeDate(2026, 12, 1)
        )
        XCTAssertEqual(bonus.remainingSpendDollars, 3_000)
        XCTAssertFalse(bonus.isMet)
        XCTAssertTrue(bonus.isOpen(asOf: Fixture.inQ3))
        XCTAssertEqual(bonus.fractionComplete, 0.25, accuracy: 0.0001)
    }

    func testOverspendCountsAsMet() {
        let bonus = WelcomeBonus(
            rewardUnits: 60_000,
            requiredSpendDollars: 4_000,
            spentDollars: 4_500,
            deadline: Fixture.makeDate(2026, 12, 1)
        )
        XCTAssertTrue(bonus.isMet)
        XCTAssertEqual(bonus.remainingSpendDollars, 0)
        XCTAssertFalse(bonus.isOpen(asOf: Fixture.inQ3))
    }
}

final class CardTests: XCTestCase {

    func testBonusCategoriesIncludeTheCurrentRotation() {
        let flex = CardCatalog.chaseFreedomFlex
        let categories = flex.bonusCategories(asOf: Fixture.inQ3)
        XCTAssertTrue(categories.contains(.dining))
        XCTAssertTrue(categories.contains(.groceries), "Q3 rotation should appear alongside the permanent rules")
        XCTAssertFalse(categories.contains(.base))
    }

    func testCardRoundTripsThroughJSON() throws {
        let original = CardCatalog.amexBlueCashPreferred
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(Card.self, from: data)
        XCTAssertEqual(original, restored)
    }

    func testWholeCatalogRoundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(CardCatalog.all)
        let restored = try JSONDecoder().decode([Card].self, from: data)
        XCTAssertEqual(restored.count, CardCatalog.all.count)
    }

    func testCatalogSearch() {
        XCTAssertEqual(CardCatalog.search("sapphire").count, 1)
        XCTAssertEqual(CardCatalog.search("chase").count, 2)
        XCTAssertTrue(CardCatalog.search("nonexistent bank").isEmpty)
        XCTAssertEqual(CardCatalog.search("  ").count, CardCatalog.all.count)
    }

    func testEveryCatalogCardDeclaresABaseRate() {
        for card in CardCatalog.all {
            XCTAssertNotNil(card.rule(for: .base), "\(card.displayName) is missing a base rule")
        }
    }
}

final class MerchantCategoryMapTests: XCTestCase {

    func testDomainLookup() {
        XCTAssertEqual(MerchantCategoryMap.category(forDomain: "amazon.com"), .onlineShopping)
        XCTAssertEqual(MerchantCategoryMap.category(forDomain: "delta.com"), .flights)
        XCTAssertEqual(MerchantCategoryMap.category(forDomain: "instacart.com"), .groceries)
    }

    func testSubdomainsResolveToTheRegistrableDomain() {
        XCTAssertEqual(MerchantCategoryMap.category(forDomain: "www.amazon.com"), .onlineShopping)
        XCTAssertEqual(MerchantCategoryMap.category(forDomain: "smile.amazon.com"), .onlineShopping)
        XCTAssertEqual(MerchantCategoryMap.category(forDomain: "WWW.Delta.COM"), .flights)
    }

    func testUnknownDomainReturnsNilRatherThanGuessing() {
        XCTAssertNil(MerchantCategoryMap.category(forDomain: "some-random-shop.example"))
        XCTAssertNil(MerchantCategoryMap.category(forDomain: "localhost"))
    }

    func testPlaceTypeLookup() {
        XCTAssertEqual(MerchantCategoryMap.category(forPlaceType: "restaurant"), .dining)
        XCTAssertEqual(MerchantCategoryMap.category(forPlaceType: "gas_station"), .gas)
        XCTAssertEqual(MerchantCategoryMap.category(forPlaceType: "supermarket"), .groceries)
    }

    /// Costco is typed as a supermarket by most place providers but does not
    /// code as one at the network level, which is what decides the reward.
    func testWarehouseClubNameOverridesThePlaceType() {
        XCTAssertEqual(
            MerchantCategoryMap.category(forPlaceType: "supermarket", merchantName: "Costco Wholesale"),
            .warehouseClub
        )
        XCTAssertEqual(
            MerchantCategoryMap.category(forPlaceTypes: ["department_store", "supermarket"], merchantName: "Sam's Club"),
            .warehouseClub
        )
    }

    func testMostSpecificPlaceTypeWins() {
        XCTAssertEqual(
            MerchantCategoryMap.category(forPlaceTypes: ["cafe", "point_of_interest", "establishment"]),
            .dining
        )
    }

    func testAmbiguousPlacesDowngradeConfidence() {
        XCTAssertEqual(MerchantCategoryMap.confidence(forPlaceTypes: ["restaurant"]), .exact)
        XCTAssertEqual(MerchantCategoryMap.confidence(forPlaceTypes: ["restaurant", "shopping_mall"]), .categoryOnly)
        XCTAssertEqual(MerchantCategoryMap.confidence(forPlaceTypes: ["airport"]), .categoryOnly)
    }

    func testFallbackListIsTwentyMerchants() {
        XCTAssertEqual(MerchantCategoryMap.topOnlineMerchants.count, 20)
    }
}
