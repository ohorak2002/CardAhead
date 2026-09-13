import XCTest
@testable import CardKit

/// Pins that would sit on top of each other, and the geofences the map is
/// allowed to say it is watching.
final class MapClusterTests: XCTestCase {

    private func result(
        _ id: String,
        types: [String] = ["restaurant"],
        metersNorth: Double,
        metersEast: Double = 0,
        opportunity: Bool = false
    ) -> MapPlaceResult {
        let latitudeStep = 1 / 111_194.93
        let longitudeStep = latitudeStep / max(0.01, cos(Fixture.anchor.latitude * .pi / 180))
        let place = MapPlace(
            id: id,
            name: id.capitalized,
            coordinate: GeoCoordinate(
                latitude: Fixture.anchor.latitude + metersNorth * latitudeStep,
                longitude: Fixture.anchor.longitude + metersEast * longitudeStep
            ),
            placeTypes: types
        )
        // `isOpportunity` reads the recommendation, so the only honest way to
        // make one is to rank a real wallet at a real category. Dining against
        // Amex Gold is a bonus rate; a gym is not a category at all.
        let engine = RecommendationEngine()
        let recommendation = opportunity
            ? place.purchaseContext().flatMap { engine.recommend(from: [CardCatalog.amexGold], in: $0) }
            : nil
        return MapPlaceResult(
            place: place,
            distanceMeters: abs(metersNorth) + abs(metersEast),
            recommendation: recommendation
        )
    }

    /// Roughly what a 40pt pin covers on a 300pt map showing a mile or so.
    private let separation = 60 / 111_194.93

    // MARK: - Grouping

    func testShopsOnTopOfEachOtherBecomeOnePin() {
        let groups = NearbyPlaces.pinGroups(
            for: [
                result("a", metersNorth: 0),
                result("b", metersNorth: 20),
                result("c", metersNorth: 35)
            ],
            separationDegrees: separation,
            referenceLatitude: Fixture.anchor.latitude
        )
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].count, 3)
        XCTAssertTrue(groups[0].isCluster)
        XCTAssertNil(groups[0].single)
    }

    func testShopsAStreetApartStayApart() {
        let groups = NearbyPlaces.pinGroups(
            for: [
                result("a", metersNorth: 0),
                result("b", metersNorth: 400),
                result("c", metersNorth: 900)
            ],
            separationDegrees: separation,
            referenceLatitude: Fixture.anchor.latitude
        )
        XCTAssertEqual(groups.count, 3)
        XCTAssertTrue(groups.allSatisfy { !$0.isCluster })
        XCTAssertEqual(groups.compactMap(\.single?.id), ["a", "b", "c"])
    }

    func testZoomedRightInNothingClusters() {
        let groups = NearbyPlaces.pinGroups(
            for: [result("a", metersNorth: 0), result("b", metersNorth: 20)],
            separationDegrees: 0,
            referenceLatitude: Fixture.anchor.latitude
        )
        XCTAssertEqual(groups.count, 2)
    }

    /// A degree of longitude is shorter than a degree of latitude everywhere
    /// but the equator, so comparing both against the same number would make
    /// the catchment an ellipse and cluster two shops that are further apart
    /// east-west than the ones it refuses to cluster north-south.
    func testTheCatchmentIsACircleOnTheGroundNotAnEllipse() {
        let northSouth = NearbyPlaces.pinGroups(
            for: [result("a", metersNorth: 0), result("b", metersNorth: 50)],
            separationDegrees: separation,
            referenceLatitude: Fixture.anchor.latitude
        )
        let eastWest = NearbyPlaces.pinGroups(
            for: [result("a", metersNorth: 0), result("b", metersNorth: 0, metersEast: 50)],
            separationDegrees: separation,
            referenceLatitude: Fixture.anchor.latitude
        )
        XCTAssertEqual(northSouth.count, 1)
        XCTAssertEqual(eastWest.count, 1, "fifty metres is fifty metres in both directions")
    }

    // MARK: - Identity and order

    func testAGroupIsNamedAfterItsLowestMemberNotItsFirst() {
        let forwards = NearbyPlaces.pinGroups(
            for: [result("z", metersNorth: 0), result("a", metersNorth: 20)],
            separationDegrees: separation,
            referenceLatitude: Fixture.anchor.latitude
        )
        let backwards = NearbyPlaces.pinGroups(
            for: [result("a", metersNorth: 20), result("z", metersNorth: 0)],
            separationDegrees: separation,
            referenceLatitude: Fixture.anchor.latitude
        )
        XCTAssertEqual(forwards[0].id, "a")
        XCTAssertEqual(
            backwards[0].id,
            forwards[0].id,
            "an identity that changes under a re-sort rebuilds every annotation on the map"
        )
    }

    func testTheSameInputAlwaysGivesTheSamePins() {
        let input = [
            result("a", metersNorth: 0),
            result("b", metersNorth: 20),
            result("c", metersNorth: 800)
        ]
        let first = NearbyPlaces.pinGroups(
            for: input,
            separationDegrees: separation,
            referenceLatitude: Fixture.anchor.latitude
        )
        let second = NearbyPlaces.pinGroups(
            for: input,
            separationDegrees: separation,
            referenceLatitude: Fixture.anchor.latitude
        )
        XCTAssertEqual(first, second)
    }

    func testMembersKeepTheOrderTheyArrivedIn() {
        let groups = NearbyPlaces.pinGroups(
            for: [result("b", metersNorth: 0), result("a", metersNorth: 20)],
            separationDegrees: separation,
            referenceLatitude: Fixture.anchor.latitude
        )
        XCTAssertEqual(
            groups[0].results.map(\.id),
            ["b", "a"],
            "the list behind a tap should match the list under the map"
        )
    }

    // MARK: - What a cluster says about itself

    func testAClusterSitsInTheMiddleOfItsMembers() {
        let groups = NearbyPlaces.pinGroups(
            for: [result("a", metersNorth: 0), result("b", metersNorth: 40)],
            separationDegrees: separation,
            referenceLatitude: Fixture.anchor.latitude
        )
        let middle = Fixture.offset(Fixture.anchor, metersNorth: 20)
        XCTAssertEqual(groups[0].coordinate.latitude, middle.latitude, accuracy: 0.000_01)
    }

    func testAClusterIsRingedWhenAnySingleMemberIsWorthIt() {
        let groups = NearbyPlaces.pinGroups(
            for: [
                result("plain", types: ["gym"], metersNorth: 0),
                result("good", metersNorth: 20, opportunity: true)
            ],
            separationDegrees: separation,
            referenceLatitude: Fixture.anchor.latitude
        )
        XCTAssertEqual(groups.count, 1)
        XCTAssertTrue(
            groups[0].hasOpportunity,
            "hiding the one good shop inside a heap defeats the point of the ring"
        )
    }

    func testAClusterTakesTheColourOfWhatIsMostlyInIt() {
        let groups = NearbyPlaces.pinGroups(
            for: [
                result("r1", types: ["restaurant"], metersNorth: 0),
                result("r2", types: ["cafe"], metersNorth: 15),
                result("g1", types: ["gas_station"], metersNorth: 25)
            ],
            separationDegrees: separation,
            referenceLatitude: Fixture.anchor.latitude
        )
        XCTAssertEqual(groups[0].dominantCategory, .restaurants)
    }

    func testItKnowsHowFarApartItsMembersAreSoATapCanZoomToThem() {
        let groups = NearbyPlaces.pinGroups(
            for: [result("a", metersNorth: 0), result("b", metersNorth: 40)],
            separationDegrees: separation,
            referenceLatitude: Fixture.anchor.latitude
        )
        XCTAssertGreaterThan(groups[0].latitudeSpread, 0)
        XCTAssertEqual(groups[0].longitudeSpread, 0, accuracy: 0.000_001)
    }

    func testTheLabelUnderACountNamesTheNearestMember() {
        let groups = NearbyPlaces.pinGroups(
            for: [result("far", metersNorth: 40), result("near", metersNorth: 5)],
            separationDegrees: separation,
            referenceLatitude: Fixture.anchor.latitude
        )
        XCTAssertEqual(groups[0].nearest?.id, "near")
    }

    // MARK: - Which shops are actually being watched

    func testThePlanNamesTheShopsInAGeofence() {
        let plan = RegionPlan(
            anchor: Fixture.anchor,
            regions: [
                Fixture.region(Fixture.merchant("p1", category: .dining, metersNorth: 100)),
                Fixture.region(Fixture.merchant("p2", category: .gas, metersNorth: 300))
            ],
            madeAt: Date()
        )
        XCTAssertEqual(plan.watchedPlaceIDs, ["p1", "p2"])
    }

    func testAnEmptyPlanWatchesNothingRatherThanEverything() {
        let plan = RegionPlan(anchor: Fixture.anchor, regions: [], madeAt: Date())
        XCTAssertTrue(plan.watchedPlaceIDs.isEmpty)
    }

    /// The join between the two halves of the app is the place provider's own
    /// id, kept by both. If that ever stops being true the map silently stops
    /// marking anything, so it is worth one test.
    func testAMapPlaceAndItsGeofenceShareAnIdentity() {
        let merchant = Fixture.merchant("place-abc", category: .dining, metersNorth: 50)
        let plan = RegionPlan(anchor: Fixture.anchor, regions: [Fixture.region(merchant)], madeAt: Date())
        let place = MapPlace(merchant)
        XCTAssertTrue(plan.watchedPlaceIDs.contains(place.id))
    }
}
