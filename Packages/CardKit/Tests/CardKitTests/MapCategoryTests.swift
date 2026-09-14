import XCTest
@testable import CardKit

/// The two axes a place sits on — what kind of shop it is, and what a card
/// pays there — and the ways they are allowed to disagree.
final class MapCategoryTests: XCTestCase {

    // MARK: - Resolving a chip

    func testResolvesTheMostSpecificCategoryRegardlessOfTypeOrder() {
        // A petrol station with a shop attached. Google very often lists the
        // shop first, and "Gas" is still the right chip.
        let gas = MapCategory.matching(placeTypes: ["convenience_store", "gas_station", "store"])
        XCTAssertEqual(gas, .gasStations)

        // A mall is also a store, and it is not a shop.
        let mall = MapCategory.matching(placeTypes: ["store", "shopping_mall", "point_of_interest"])
        XCTAssertEqual(mall, .malls)
    }

    func testAnUnrecognisedPlaceIsOtherRatherThanDropped() {
        XCTAssertEqual(MapCategory.matching(placeTypes: ["insurance_agency"]), .other)
        XCTAssertEqual(MapCategory.matching(placeTypes: []), .other)
    }

    func testEveryCategoryResolvesToItself() {
        for category in MapCategory.allCases {
            for type in category.placeTypes {
                // Not an assertion that it comes back as `category` — a type
                // listed under two chips resolves to the higher-priority one
                // on purpose. What must hold is that it never falls through to
                // `other`, which would mean a type we ask for and then bin.
                guard category != .other else { continue }
                XCTAssertNotEqual(
                    MapCategory.matching(placeTypes: [type]),
                    .other,
                    "\(type) is requested for \(category.rawValue) but resolves to nothing"
                )
            }
        }
    }

    func testAskingForEverythingAsksForEveryTypeOnce() {
        let all = MapCategory.placeTypes(for: [])
        XCTAssertEqual(all.count, Set(all).count, "duplicate types waste the 50-type ceiling")
        XCTAssertTrue(all.contains("restaurant"))
        XCTAssertTrue(all.contains("shopping_mall"))
        XCTAssertTrue(all.contains("gas_station"))
        XCTAssertLessThanOrEqual(all.count, GooglePlaceSearchSource.maximumIncludedTypes)
    }

    func testAskingForOneCategoryAsksOnlyForItsTypes() {
        let types = MapCategory.placeTypes(for: [.groceries])
        XCTAssertTrue(types.contains("supermarket"))
        XCTAssertFalse(types.contains("restaurant"))
    }

    // MARK: - The other axis

    func testAPlaceCanHaveAChipAndNoEarningCategory() {
        let gym = MapPlace(
            id: "g",
            name: "Neighbourhood Gym",
            coordinate: GeoCoordinate(latitude: 33.78, longitude: -84.38),
            placeTypes: ["gym"]
        )
        XCTAssertEqual(gym.mapCategory, .other)
        XCTAssertNil(gym.spendingCategory, "nothing in the wallet earns extra at a gym, and that is not a guess to be made")
        XCTAssertNil(gym.purchaseContext())
        XCTAssertNil(gym.asMerchant, "a place with no earning category must never take one of the twenty geofences")
    }

    func testAPharmacyIsOtherOnTheMapAndStillEarnsAtDrugstoreRates() {
        let pharmacy = MapPlace(
            id: "p",
            name: "Walgreens",
            coordinate: GeoCoordinate(latitude: 33.78, longitude: -84.38),
            placeTypes: ["pharmacy", "store"]
        )
        XCTAssertEqual(pharmacy.mapCategory, .other, "nobody filters a map by drugstore")
        XCTAssertEqual(pharmacy.spendingCategory, .drugstores, "but a card certainly pays differently there")
    }

    func testAMallWithholdsItsNameFromARecommendation() {
        let mall = MapPlace(
            id: "m",
            name: "Lenox Square",
            coordinate: GeoCoordinate(latitude: 33.84, longitude: -84.36),
            placeTypes: ["shopping_mall"]
        )
        XCTAssertEqual(mall.mapCategory, .malls)
        XCTAssertEqual(mall.confidence, .categoryOnly)
        XCTAssertNil(mall.purchaseContext()?.merchantName, "one set of coordinates, a hundred tills")
    }

    func testAMerchantBecomesAPlaceAndBack() {
        let merchant = Merchant(
            id: "m1",
            name: "Corner Bistro",
            coordinate: GeoCoordinate(latitude: 33.78, longitude: -84.38),
            placeTypes: ["restaurant"],
            category: .dining
        )
        let place = MapPlace(merchant)
        XCTAssertEqual(place.mapCategory, .restaurants)
        XCTAssertEqual(place.spendingCategory, .dining)
        XCTAssertEqual(place.asMerchant, merchant)
    }

    func testSubtitleFallsBackToTheChipRatherThanBeingBlank() {
        let unnamed = MapPlace(
            id: "u",
            name: "Somewhere",
            coordinate: GeoCoordinate(latitude: 33.78, longitude: -84.38),
            placeTypes: ["restaurant"]
        )
        XCTAssertEqual(unnamed.subtitle, MapCategory.restaurants.displayName)

        var named = unnamed
        named.typeDescription = "Steakhouse"
        XCTAssertEqual(named.subtitle, "Steakhouse")
    }
}
