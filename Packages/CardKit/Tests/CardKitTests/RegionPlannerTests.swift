import XCTest
@testable import CardKit

/// The half of region monitoring that can be tested without walking around a
/// city: which places get watched, in what order, and when the set is redrawn.
final class RegionPlannerTests: XCTestCase {

    let planner = RegionPlanner()

    // MARK: - Distance

    func testDistanceToSelfIsZero() {
        XCTAssertEqual(Fixture.anchor.distance(to: Fixture.anchor), 0, accuracy: 0.0001)
    }

    func testOneDegreeOfLatitudeIsAboutOneHundredElevenKilometres() {
        let north = GeoCoordinate(latitude: 41.7580, longitude: -73.9855)
        XCTAssertEqual(Fixture.anchor.distance(to: north), 111_195, accuracy: 200)
    }

    /// Longitude narrows towards the poles, and a planner that ignored that
    /// would rank shops to the east and west as further away than they are.
    func testLongitudeDistanceShrinksWithLatitude() {
        let atEquator = GeoCoordinate(latitude: 0, longitude: 0)
            .distance(to: GeoCoordinate(latitude: 0, longitude: 0.01))
        let atSixty = GeoCoordinate(latitude: 60, longitude: 0)
            .distance(to: GeoCoordinate(latitude: 60, longitude: 0.01))
        XCTAssertEqual(atSixty / atEquator, 0.5, accuracy: 0.01)
    }

    func testOffsetHelperProducesTheDistanceItClaims() {
        let there = Fixture.offset(Fixture.anchor, metersNorth: 300)
        XCTAssertEqual(Fixture.anchor.distance(to: there), 300, accuracy: 1)
    }

    func testNullIslandIsNotAValidCoordinate() {
        XCTAssertFalse(GeoCoordinate(latitude: 0, longitude: 0).isValid)
        XCTAssertFalse(GeoCoordinate(latitude: 91, longitude: 0).isValid)
        XCTAssertTrue(Fixture.anchor.isValid)
    }

    // MARK: - Relevance

    func testFlatRateWalletMakesNothingRelevant() {
        let wallet = [CardCatalog.citiDoubleCash, CardCatalog.wellsFargoActiveCash]
        XCTAssertTrue(planner.relevantCategories(in: wallet, asOf: Fixture.inQ3).isEmpty)
    }

    func testBonusCategoriesAreRelevant() {
        let categories = planner.relevantCategories(in: [CardCatalog.amexGold], asOf: Fixture.inQ3)
        XCTAssertTrue(categories.contains(.dining))
        XCTAssertTrue(categories.contains(.groceries))
        XCTAssertFalse(categories.contains(.base))
    }

    /// A rotating bonus is only worth a geofence during its own quarter. Built
    /// here rather than taken from the catalog so the test keeps its meaning
    /// whatever the catalog's rotation says this year.
    func testOnlyTheCurrentQuartersRotationIsRelevant() {
        let card = Card(
            issuer: "Test",
            name: "Rotator",
            rules: [CategoryRule(category: .base, rate: 1)],
            rotatingProgram: RotatingProgram(
                rate: 5,
                quarters: [
                    RotatingQuarter(quarter: Fixture.q3, categories: [.gas]),
                    RotatingQuarter(quarter: Quarter(year: 2026, index: 4), categories: [.drugstores])
                ]
            )
        )
        let categories = planner.relevantCategories(in: [card], asOf: Fixture.inQ3)
        XCTAssertEqual(categories, [.gas])
    }

    /// Adding a card is what makes a whole category worth watching, and the
    /// monitor decides whether to redraw by comparing these two sets.
    func testAddingACardWidensWhatIsRelevant() {
        let before = planner.relevantCategories(in: [CardCatalog.citiDoubleCash], asOf: Fixture.inQ3)
        let after = planner.relevantCategories(
            in: [CardCatalog.citiDoubleCash, CardCatalog.amexGold],
            asOf: Fixture.inQ3
        )
        XCTAssertTrue(before.isEmpty)
        XCTAssertTrue(after.isSuperset(of: [.dining, .groceries]))
    }

    // MARK: - Planning

    private var diningWallet: [Card] { [CardCatalog.amexGold] }

    func testPlanKeepsOnlyTheNearestTwenty() {
        let merchants = (1...45).map {
            Fixture.merchant("m\($0)", category: .dining, metersNorth: Double($0) * 20)
        }
        let plan = planner.plan(
            around: Fixture.anchor,
            merchants: merchants.shuffled(),
            cards: diningWallet,
            asOf: Fixture.inQ3
        )
        XCTAssertEqual(plan.regions.count, 20)
        XCTAssertEqual(plan.regions.map(\.merchant.id), (1...20).map { "m\($0)" })
    }

    func testPlanIsOrderedNearestFirst() {
        let merchants = [
            Fixture.merchant("far", category: .dining, metersNorth: 900),
            Fixture.merchant("near", category: .dining, metersNorth: 50),
            Fixture.merchant("middle", category: .dining, metersNorth: 300)
        ]
        let plan = planner.plan(around: Fixture.anchor, merchants: merchants, cards: diningWallet, asOf: Fixture.inQ3)
        XCTAssertEqual(plan.regions.map(\.merchant.id), ["near", "middle", "far"])
        XCTAssertEqual(plan.regions[0].distanceMeters, 50, accuracy: 1)
        XCTAssertEqual(plan.farthestDistanceMeters, 900, accuracy: 1)
    }

    /// A shop nobody in this wallet earns extra at is a shop not worth one of
    /// the twenty slots, however close it is.
    func testIrrelevantCategoriesAreSkippedEvenWhenCloser() {
        let merchants = [
            Fixture.merchant("petrol", category: .gas, metersNorth: 10),
            Fixture.merchant("bistro", category: .dining, metersNorth: 800)
        ]
        let plan = planner.plan(around: Fixture.anchor, merchants: merchants, cards: diningWallet, asOf: Fixture.inQ3)
        XCTAssertEqual(plan.regions.map(\.merchant.id), ["bistro"])
    }

    func testFlatRateWalletRegistersNothing() {
        let merchants = [Fixture.merchant("bistro", category: .dining, metersNorth: 40)]
        let plan = planner.plan(
            around: Fixture.anchor,
            merchants: merchants,
            cards: [CardCatalog.citiDoubleCash],
            asOf: Fixture.inQ3
        )
        XCTAssertTrue(plan.regions.isEmpty)
    }

    func testInvalidCoordinatesAreDropped() {
        let broken = Merchant(
            id: "broken",
            name: "Nowhere",
            coordinate: GeoCoordinate(latitude: 0, longitude: 0),
            category: .dining
        )
        let plan = planner.plan(
            around: Fixture.anchor,
            merchants: [broken, Fixture.merchant("bistro", category: .dining, metersNorth: 40)],
            cards: diningWallet,
            asOf: Fixture.inQ3
        )
        XCTAssertEqual(plan.regions.map(\.merchant.id), ["bistro"])
    }

    /// The same place arriving twice in one response must not burn two of the
    /// twenty slots, and must not register the same identifier twice.
    func testDuplicateMerchantIDsCollapse() {
        let one = Fixture.merchant("bistro", category: .dining, metersNorth: 40)
        let again = Fixture.merchant("bistro", category: .dining, metersNorth: 60)
        let plan = planner.plan(around: Fixture.anchor, merchants: [one, again], cards: diningWallet, asOf: Fixture.inQ3)
        XCTAssertEqual(plan.regions.count, 1)
    }

    /// Two shops at the same distance must always come out in the same order,
    /// or a refresh that discovered nothing new would still tear down and
    /// re-register twenty regions.
    func testEqualDistancesSortStably() {
        let merchants = [
            Fixture.merchant("zeta", category: .dining, metersNorth: 100),
            Fixture.merchant("alpha", category: .dining, metersNorth: 100)
        ]
        let first = planner.plan(around: Fixture.anchor, merchants: merchants, cards: diningWallet, asOf: Fixture.inQ3)
        let second = planner.plan(around: Fixture.anchor, merchants: merchants.reversed(), cards: diningWallet, asOf: Fixture.inQ3)
        XCTAssertEqual(first.regions.map(\.id), second.regions.map(\.id))
        XCTAssertEqual(first.regions.map(\.merchant.id), ["alpha", "zeta"])
    }

    func testLimitIsCappedAtApplesTwenty() {
        XCTAssertEqual(RegionPlanner(limit: 60).limit, 20)
        XCTAssertEqual(RegionPlanner(limit: 5).limit, 5)
    }

    func testRegionIdentifiersAreNamespaced() {
        let merchant = Fixture.merchant("bistro", category: .dining, metersNorth: 10)
        let id = RegionPlanner.regionID(for: merchant)
        XCTAssertEqual(id, "merchant.bistro")
        XCTAssertTrue(RegionPlanner.isOurs(regionID: id))
        XCTAssertFalse(RegionPlanner.isOurs(regionID: "something.else"))
    }

    // MARK: - Staying current

    private func populatedPlan(farthest: Double = 800) -> RegionPlan {
        let merchants = [
            Fixture.merchant("near", category: .dining, metersNorth: 100),
            Fixture.merchant("far", category: .dining, metersNorth: farthest)
        ]
        return planner.plan(around: Fixture.anchor, merchants: merchants, cards: diningWallet, asOf: Fixture.inQ3)
    }

    func testNoPlanAlwaysNeedsOne() {
        XCTAssertTrue(planner.needsRefresh(nil, at: Fixture.anchor, asOf: Fixture.inQ3))
    }

    func testStandingStillDoesNotRedrawThePlan() {
        XCTAssertFalse(planner.needsRefresh(populatedPlan(), at: Fixture.anchor, asOf: Fixture.inQ3))
    }

    func testMovingAcrossTownRedrawsThePlan() {
        let moved = Fixture.offset(Fixture.anchor, metersNorth: 4_000)
        XCTAssertTrue(planner.needsRefresh(populatedPlan(), at: moved, asOf: Fixture.inQ3))
    }

    /// Half the reach of the current plan is enough, because at that point the
    /// twenty nearest from here are no longer the twenty nearest from there.
    func testMovingHalfTheReachRedrawsThePlan() {
        let plan = populatedPlan(farthest: 800)
        let justShort = Fixture.offset(Fixture.anchor, metersNorth: 380)
        let pastIt = Fixture.offset(Fixture.anchor, metersNorth: 420)
        XCTAssertFalse(planner.needsRefresh(plan, at: justShort, asOf: Fixture.inQ3))
        XCTAssertTrue(planner.needsRefresh(plan, at: pastIt, asOf: Fixture.inQ3))
    }

    /// Nothing relevant nearby is not a stable answer — a block away it may be
    /// a different one, so an empty plan is cheap to retry.
    func testAnEmptyPlanRetriesOnAnyMovement() {
        let empty = RegionPlan(anchor: Fixture.anchor, regions: [], madeAt: Fixture.inQ3)
        let nudged = Fixture.offset(Fixture.anchor, metersNorth: 60)
        XCTAssertTrue(planner.needsRefresh(empty, at: nudged, asOf: Fixture.inQ3))
        XCTAssertFalse(planner.needsRefresh(empty, at: Fixture.anchor, asOf: Fixture.inQ3))
    }

    func testAnOldPlanIsRedrawnEvenWithoutMoving() {
        let plan = populatedPlan()
        let tomorrow = Fixture.inQ3.addingTimeInterval(60 * 60 * 25)
        XCTAssertTrue(planner.needsRefresh(plan, at: Fixture.anchor, asOf: tomorrow))
    }

    /// A rubbish fix should not tear down a working plan.
    func testAnInvalidFixIsIgnored() {
        XCTAssertFalse(planner.needsRefresh(
            populatedPlan(),
            at: GeoCoordinate(latitude: 0, longitude: 0),
            asOf: Fixture.inQ3
        ))
    }

    // MARK: - Building merchants from provider output

    func testProviderTypesBecomeACategory() throws {
        let merchant = try XCTUnwrap(Merchant.from(
            id: "abc",
            name: "Corner Bistro",
            coordinate: Fixture.anchor,
            placeTypes: ["restaurant", "point_of_interest"]
        ))
        XCTAssertEqual(merchant.category, .dining)
    }

    /// A mall cannot be resolved to one till, so the reminder must name the
    /// category rather than a shop inside it.
    func testAmbiguousPlacesComeBackAsCategoryOnly() throws {
        let mall = try XCTUnwrap(Merchant.from(
            id: "mall",
            name: "Riverside Centre",
            coordinate: Fixture.anchor,
            placeTypes: ["shopping_mall"]
        ))
        XCTAssertEqual(mall.confidence, .categoryOnly)
    }

    /// Costco is typed as a supermarket or department store by every provider
    /// and codes as neither at the network level, which is what pays the reward.
    func testWarehouseClubNameBeatsTheProvidersType() throws {
        let club = try XCTUnwrap(Merchant.from(
            id: "costco-1",
            name: "Costco Wholesale",
            coordinate: Fixture.anchor,
            placeTypes: ["department_store"]
        ))
        XCTAssertEqual(club.category, .warehouseClub)
    }

    /// A place we cannot map is not a place we guess at.
    func testUnmappableTypesProduceNothing() {
        XCTAssertNil(Merchant.from(
            id: "mystery",
            name: "Something",
            coordinate: Fixture.anchor,
            placeTypes: ["funeral_home", "locksmith"]
        ))
    }

    func testAStaticSourceOnlyReturnsWhatIsInRange() async throws {
        let source = StaticMerchantSource([
            Fixture.merchant("near", category: .dining, metersNorth: 200),
            Fixture.merchant("far", category: .dining, metersNorth: 5_000)
        ])
        let found = try await source.merchants(near: Fixture.anchor, radiusMeters: 1_000)
        XCTAssertEqual(found.map(\.id), ["near"])
    }
}
