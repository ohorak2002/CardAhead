import XCTest
@testable import CardKit

/// The test for the bug that only a real phone could find.
///
/// CardAhead's Map came back from its first outing on a handset showing
/// "Could not look up nearby places. The place lookup was refused (400).
/// Unsupported types: grocery_or_supermarket." and **zero** pins — not zero
/// grocers, zero everything, because one unrecognised entry in `includedTypes`
/// fails the whole `searchNearby` request rather than its own slice of it.
///
/// CI could not have caught it and still cannot: the screenshot job seeds its
/// own places and never calls Google, so the live API had never once been
/// asked a question until the app was on a phone. What *can* be pinned is the
/// thing that went wrong underneath — one array being used both to read a
/// response and to phrase a request, when only the first of those jobs wants
/// the legacy aliases.
final class PlaceRequestVocabularyTests: XCTestCase {

    // MARK: - The rule

    /// Nothing Google will refuse may reach `includedTypes`.
    func testNoLegacyTypeCanReachARequest() {
        for category in MapCategory.allCases {
            for type in category.requestableTypes {
                XCTAssertFalse(
                    PlaceTypeVocabulary.legacyOnly.contains(type),
                    """
                    \(category.displayName) would ask Places for "\(type)", which the new API \
                    refuses. One bad entry fails the entire request, so this is not a missing \
                    category — it is an empty map.
                    """
                )
            }
        }
    }

    /// The same rule at the only place that actually builds the request.
    func testTheAssembledRequestListIsClean() {
        let everything = Set(MapCategory.allCases)
        let asked = Set(MapCategory.placeTypes(for: everything))
        XCTAssertTrue(
            asked.isDisjoint(with: PlaceTypeVocabulary.legacyOnly),
            "placeTypes(for:) let a legacy alias through: \(asked.intersection(PlaceTypeVocabulary.legacyOnly).sorted())"
        )

        // And for each category on its own, since the filter sheet asks for
        // subsets far more often than it asks for everything.
        for category in MapCategory.allCases {
            let subset = Set(MapCategory.placeTypes(for: [category]))
            XCTAssertTrue(
                subset.isDisjoint(with: PlaceTypeVocabulary.legacyOnly),
                "\(category.displayName) alone still asks for a legacy alias."
            )
        }
    }

    /// The specific string the phone reported, pinned by name so nobody
    /// reintroduces it while tidying the vocabulary.
    func testTheTypeThatBrokeTheMapIsNeverRequested() {
        XCTAssertFalse(
            MapCategory.placeTypes(for: [.groceries]).contains("grocery_or_supermarket"),
            "This is the exact type that returned a 400 and emptied the whole map."
        )
    }

    // MARK: - What must not be lost in the process

    /// Dropping a type from the *request* must not drop it from *reading*.
    /// A place that comes back tagged `grocery_or_supermarket` is a grocer
    /// whatever generation of the API named it.
    func testALegacyTypeIsStillUnderstoodInAResponse() {
        XCTAssertEqual(MapCategory.matching(placeTypes: ["grocery_or_supermarket"]), .groceries)
        XCTAssertEqual(MapCategory.matching(placeTypes: ["lodging"]), .hotels)
        XCTAssertEqual(
            MapCategory.matching(placeTypes: ["grocery_or_supermarket", "store"]),
            .groceries,
            "The specific type must still beat the catch-all when it arrives as a legacy alias."
        )
    }

    /// Every category still has something to ask for. A category that asks for
    /// nothing silently returns nothing, which is the same broken map arrived
    /// at from the other direction.
    func testEveryCategoryCanStillAskForSomething() {
        for category in MapCategory.allCases {
            XCTAssertFalse(
                category.requestableTypes.isEmpty,
                "\(category.displayName) has no requestable type left and would match nothing."
            )
        }
    }

    /// The removals each had a live sibling covering them — that is why they
    /// were free, and this pins that claim.
    func testEachRemovedTypeIsCoveredByASibling() {
        XCTAssertTrue(MapCategory.groceries.requestableTypes.contains("grocery_store"))
        XCTAssertTrue(MapCategory.groceries.requestableTypes.contains("supermarket"))
        XCTAssertTrue(MapCategory.hotels.requestableTypes.contains("hotel"))
        XCTAssertTrue(MapCategory.malls.requestableTypes.contains("shopping_mall"))
    }

    // MARK: - The other half of the app, which had the same bug

    /// **The geofence planner made the identical mistake and fails silently.**
    /// `MerchantCategoryMap` is the reading vocabulary for the reminder path
    /// and was handing its legacy aliases straight to `includedTypes` as well.
    /// A refused lookup there means no merchants, so no regions, so no
    /// reminders — and unlike the Map, nothing appears on screen to say so. It
    /// looks exactly like a week where nothing happened to be nearby.
    func testTheGeofencePlannerNeverAsksForALegacyType() {
        for category in SpendingCategory.allCases {
            let asked = Set(MerchantCategoryMap.placeTypeNames(for: [category]))
            XCTAssertTrue(
                asked.isDisjoint(with: PlaceTypeVocabulary.legacyOnly),
                """
                The geofence lookup for \(category) would ask for \
                \(asked.intersection(PlaceTypeVocabulary.legacyOnly).sorted()). That refusal is \
                invisible: no merchants, no regions, no reminders, and no error anywhere.
                """
            )
        }

        let everything = Set(MerchantCategoryMap.placeTypeNames(for: Set(SpendingCategory.allCases)))
        XCTAssertTrue(everything.isDisjoint(with: PlaceTypeVocabulary.legacyOnly))
    }

    /// Same rule as the Map's: dropping it from the request must not drop it
    /// from reading. A shop that comes back as `grocery_or_supermarket` still
    /// has to earn at the groceries rate.
    func testTheGeofencePlannerStillReadsALegacyType() {
        XCTAssertEqual(
            MerchantCategoryMap.category(forPlaceTypes: ["grocery_or_supermarket"], merchantName: "Corner Shop"),
            .groceries
        )
        XCTAssertEqual(
            MerchantCategoryMap.category(forPlaceTypes: ["lodging"], merchantName: "Somewhere Inn"),
            .hotels
        )
    }

    /// **No category may lose its last searchable type to this filter.**
    ///
    /// Not every spending category has a shopfront — `onlineShopping` has
    /// nowhere to stand outside of — so an empty list is legitimate in
    /// general. What must never happen is a category that *did* have types
    /// being emptied by the legacy filter, because the result is a category
    /// the planner can no longer find merchants for, and that failure is
    /// silent. These three are the ones the filter actually touches.
    func testTheFilterNeverEmptiesACategoryItTouches() {
        for (category, survivor) in [
            (SpendingCategory.groceries, "grocery_store"),
            (SpendingCategory.hotels, "hotel"),
            (SpendingCategory.dining, "restaurant")
        ] {
            let asked = MerchantCategoryMap.placeTypeNames(for: [category])
            XCTAssertTrue(
                asked.contains(survivor),
                "\(category) lost \(survivor); the legacy filter has gone too far."
            )
        }
    }
}
