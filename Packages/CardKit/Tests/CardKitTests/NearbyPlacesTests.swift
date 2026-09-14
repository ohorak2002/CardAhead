import XCTest
@testable import CardKit

/// The map's list, before any of it is drawn: what is in range, what a card
/// pays there, and what order it all comes in.
final class NearbyPlacesTests: XCTestCase {

    private func place(
        _ id: String,
        types: [String],
        metersNorth: Double,
        name: String? = nil,
        rating: Double? = nil
    ) -> MapPlace {
        MapPlace(
            id: id,
            name: name ?? id.capitalized,
            coordinate: Fixture.offset(Fixture.anchor, metersNorth: metersNorth),
            placeTypes: types,
            rating: rating
        )
    }

    private var wallet: [Card] {
        [CardCatalog.amexGold, CardCatalog.citiDoubleCash]
    }

    // MARK: - The filter

    func testEmptyCategoriesMeansEverythingRatherThanNothing() {
        let filter = MapFilter()
        XCTAssertTrue(filter.isShowingEverything)
        XCTAssertEqual(filter.effectiveCategories, Set(MapCategory.allCases))
        for category in MapCategory.allCases {
            XCTAssertTrue(filter.includes(category))
        }
    }

    func testUntickingTheLastCategoryShowsEverythingAgain() {
        var filter = MapFilter()
        filter.showOnly(.restaurants)
        XCTAssertFalse(filter.isShowingEverything)

        filter.toggle(.restaurants)
        XCTAssertTrue(filter.isShowingEverything, "a map with no categories on it is a dead end")
    }

    func testUntickingOneOfAllLeavesTheRest() {
        var filter = MapFilter()
        filter.toggle(.hotels)
        XCTAssertFalse(filter.includes(.hotels))
        XCTAssertTrue(filter.includes(.restaurants))
    }

    func testDistanceDecidesWhatIsInRange() {
        let places = [
            place("near", types: ["restaurant"], metersNorth: 400),
            place("far", types: ["restaurant"], metersNorth: 4_000)
        ]
        var filter = MapFilter(distance: .halfMile)
        XCTAssertEqual(
            NearbyPlaces.results(from: places, near: Fixture.anchor, cards: wallet, filter: filter).map(\.id),
            ["near"]
        )

        filter.distance = .threeMiles
        XCTAssertEqual(
            Set(NearbyPlaces.results(from: places, near: Fixture.anchor, cards: wallet, filter: filter).map(\.id)),
            ["near", "far"]
        )
    }

    func testCategoryFilterAppliesToTheResolvedChipNotTheRawTypes() {
        let places = [
            place("mall", types: ["shopping_mall", "store"], metersNorth: 100),
            place("shop", types: ["clothing_store", "store"], metersNorth: 200)
        ]
        var filter = MapFilter()
        filter.showOnly(.malls)
        XCTAssertEqual(
            NearbyPlaces.results(from: places, near: Fixture.anchor, cards: wallet, filter: filter).map(\.id),
            ["mall"]
        )
    }

    func testAPlaceWithoutValidCoordinatesIsDropped() {
        let broken = MapPlace(
            id: "nowhere",
            name: "Null Island",
            coordinate: GeoCoordinate(latitude: 0, longitude: 0),
            placeTypes: ["restaurant"]
        )
        XCTAssertTrue(NearbyPlaces.results(from: [broken], near: Fixture.anchor, cards: wallet).isEmpty)
    }

    func testTheSameShopTwiceIsOneRow() {
        let duplicated = [
            place("p1", types: ["restaurant"], metersNorth: 100),
            place("p1", types: ["restaurant"], metersNorth: 100)
        ]
        XCTAssertEqual(NearbyPlaces.results(from: duplicated, near: Fixture.anchor, cards: wallet).count, 1)
    }

    // MARK: - What a card pays there

    func testARestaurantNamesACardAndAGymDoesNot() {
        let places = [
            place("bistro", types: ["restaurant"], metersNorth: 100, name: "Corner Bistro"),
            place("gym", types: ["gym"], metersNorth: 150, name: "Gym")
        ]
        let results = NearbyPlaces.results(from: places, near: Fixture.anchor, cards: wallet)

        let bistro = results.first { $0.id == "bistro" }
        XCTAssertNotNil(bistro?.recommendation)
        XCTAssertNotNil(bistro?.rewardLine)

        let gym = results.first { $0.id == "gym" }
        XCTAssertNotNil(gym, "a place nothing earns at is still a pin")
        XCTAssertNil(gym?.recommendation)
        XCTAssertNil(gym?.rewardLine)
        XCTAssertFalse(gym?.isOpportunity ?? true)
    }

    func testAnEmptyWalletRanksNothingAndStillShowsThePlaces() {
        let places = [place("bistro", types: ["restaurant"], metersNorth: 100)]
        let results = NearbyPlaces.results(from: places, near: Fixture.anchor, cards: [])
        XCTAssertEqual(results.count, 1)
        XCTAssertNil(results[0].recommendation)
    }

    func testOnlyABonusRateCountsAsAnOpportunity() {
        // Citi Double Cash pays its flat rate everywhere, so nowhere it is the
        // winner is a place worth being told about.
        let flatOnly = [CardCatalog.citiDoubleCash]
        let places = [place("gasbar", types: ["gas_station"], metersNorth: 100)]
        let results = NearbyPlaces.results(from: places, near: Fixture.anchor, cards: flatOnly)

        XCTAssertNotNil(results.first?.recommendation, "it still says which card to use")
        XCTAssertEqual(
            NearbyPlaces.opportunityCount(in: results),
            0,
            "but nothing here changes which card you would have reached for anyway"
        )
    }

    func testABonusCategoryIsAnOpportunity() {
        let places = [place("bistro", types: ["restaurant"], metersNorth: 100)]
        let results = NearbyPlaces.results(from: places, near: Fixture.anchor, cards: wallet)
        XCTAssertEqual(NearbyPlaces.opportunityCount(in: results), 1)
    }

    func testRewardLineReadsAsASentence() {
        let places = [place("bistro", types: ["restaurant"], metersNorth: 100)]
        let line = NearbyPlaces.results(from: places, near: Fixture.anchor, cards: wallet).first?.rewardLine
        let unwrapped = line ?? ""
        XCTAssertTrue(unwrapped.contains(" with "), "got \(unwrapped)")
        // Not an exact string: the catalog's rates are re-audited, and a test
        // that pins "4x" fails the next time somebody reads the issuer's page.
        XCTAssertTrue(
            unwrapped.contains("points") || unwrapped.contains("back") || unwrapped.contains("miles"),
            "got \(unwrapped)"
        )
    }

    // MARK: - Order

    func testNearestIsTheDefaultOrder() {
        let places = [
            place("far", types: ["restaurant"], metersNorth: 800),
            place("near", types: ["restaurant"], metersNorth: 100),
            place("middle", types: ["restaurant"], metersNorth: 400)
        ]
        XCTAssertEqual(
            NearbyPlaces.results(from: places, near: Fixture.anchor, cards: wallet).map(\.id),
            ["near", "middle", "far"]
        )
    }

    func testBestRewardPutsTheBonusCategoryFirst() {
        let places = [
            place("gasbar", types: ["gas_station"], metersNorth: 50),
            place("bistro", types: ["restaurant"], metersNorth: 900)
        ]
        let filter = MapFilter(sort: .bestReward)
        let results = NearbyPlaces.results(from: places, near: Fixture.anchor, cards: wallet, filter: filter)
        XCTAssertEqual(results.first?.id, "bistro", "a 4x restaurant outranks a nearer 1x forecourt")
    }

    func testUnratedPlacesSortLastRatherThanAsZeroStars() {
        let places = [
            place("unrated", types: ["restaurant"], metersNorth: 50),
            place("good", types: ["restaurant"], metersNorth: 900, rating: 4.6),
            place("poor", types: ["restaurant"], metersNorth: 950, rating: 2.1)
        ]
        let filter = MapFilter(sort: .topRated)
        XCTAssertEqual(
            NearbyPlaces.results(from: places, near: Fixture.anchor, cards: wallet, filter: filter).map(\.id),
            ["good", "poor", "unrated"]
        )
    }

    func testOrderIsStableForIdenticalInput() {
        // Two shops the same distance away. Without the id tiebreak these swap
        // between refreshes, which looks like the list flickering for no reason.
        let places = [
            place("b", types: ["restaurant"], metersNorth: 300),
            place("a", types: ["restaurant"], metersNorth: 300)
        ]
        XCTAssertEqual(
            NearbyPlaces.results(from: places, near: Fixture.anchor, cards: wallet).map(\.id),
            ["a", "b"]
        )
    }

    // MARK: - Counting

    func testCountsAreByChip() {
        let places = [
            place("r1", types: ["restaurant"], metersNorth: 100),
            place("r2", types: ["cafe"], metersNorth: 200),
            place("g1", types: ["gas_station"], metersNorth: 300)
        ]
        let counts = NearbyPlaces.counts(in: NearbyPlaces.results(from: places, near: Fixture.anchor, cards: wallet))
        XCTAssertEqual(counts[.restaurants], 2)
        XCTAssertEqual(counts[.gasStations], 1)
        XCTAssertNil(counts[.hotels])
    }

    // MARK: - Distances, said out loud

    func testDistanceTextUsesMetresUpCloseAndMilesFurtherOut() {
        let close = MapPlaceResult(
            place: place("a", types: ["restaurant"], metersNorth: 40),
            distanceMeters: 40,
            recommendation: nil
        )
        XCTAssertTrue(close.distanceText.hasSuffix(" m"), "got \(close.distanceText)")

        let away = MapPlaceResult(
            place: place("b", types: ["restaurant"], metersNorth: 800),
            distanceMeters: 800,
            recommendation: nil
        )
        XCTAssertTrue(away.distanceText.hasSuffix(" mi"), "got \(away.distanceText)")
    }

    func testFilterSummarySaysWhatIsOnScreen() {
        var filter = MapFilter(distance: .threeMiles)
        XCTAssertEqual(filter.summary, "Everything within 3 miles")

        filter.showOnly(.restaurants)
        XCTAssertEqual(filter.summary, "Restaurants within 3 miles")

        filter.toggle(.hotels)
        XCTAssertEqual(filter.summary, "Restaurants and Hotels within 3 miles")
    }
}
