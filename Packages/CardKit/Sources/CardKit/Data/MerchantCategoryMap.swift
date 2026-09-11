import Foundation

/// Turns "where the user is" or "what site they are on" into a spending category.
///
/// Two lookups, deliberately kept apart:
/// - `category(forDomain:)` backs the Safari extension. It sees a hostname and
///   nothing else — no page content, no form fields, no credentials.
/// - `category(forPlaceType:)` backs the geofence path, mapping a Google Places
///   type onto the same set of buckets.
public enum MerchantCategoryMap {

    // MARK: - Online

    private static let domains: [String: SpendingCategory] = [
        "amazon.com": .onlineShopping,
        "ebay.com": .onlineShopping,
        "etsy.com": .onlineShopping,
        "walmart.com": .onlineShopping,
        "target.com": .departmentStore,
        "macys.com": .departmentStore,
        "nordstrom.com": .departmentStore,
        "kohls.com": .departmentStore,
        "instacart.com": .groceries,
        "wholefoodsmarket.com": .groceries,
        "kroger.com": .groceries,
        "safeway.com": .groceries,
        "costco.com": .warehouseClub,
        "samsclub.com": .warehouseClub,
        "bjs.com": .warehouseClub,
        "delta.com": .flights,
        "united.com": .flights,
        "aa.com": .flights,
        "southwest.com": .flights,
        "expedia.com": .travel,
        "booking.com": .travel,
        "kayak.com": .travel,
        "airbnb.com": .travel,
        "marriott.com": .hotels,
        "hilton.com": .hotels,
        "hyatt.com": .hotels,
        "uber.com": .rideshare,
        "lyft.com": .rideshare,
        "doordash.com": .dining,
        "ubereats.com": .dining,
        "grubhub.com": .dining,
        "opentable.com": .dining,
        "netflix.com": .streaming,
        "spotify.com": .streaming,
        "hulu.com": .streaming,
        "cvs.com": .drugstores,
        "walgreens.com": .drugstores,
        "homedepot.com": .homeImprovement,
        "lowes.com": .homeImprovement,
        "ticketmaster.com": .entertainment,
        "stubhub.com": .entertainment
    ]

    /// The 20 merchants offered in the "I am buying from..." fallback when the
    /// user declines the Safari extension.
    public static var topOnlineMerchants: [(domain: String, category: SpendingCategory)] {
        let preferred = [
            "amazon.com", "target.com", "walmart.com", "instacart.com", "costco.com",
            "doordash.com", "ubereats.com", "delta.com", "united.com", "southwest.com",
            "expedia.com", "airbnb.com", "marriott.com", "uber.com", "lyft.com",
            "netflix.com", "spotify.com", "cvs.com", "homedepot.com", "ebay.com"
        ]
        return preferred.compactMap { domain in
            domains[domain].map { (domain, $0) }
        }
    }

    /// Matches the registrable domain, so `smile.amazon.com` and `www.amazon.com`
    /// both resolve. Falls back to nil rather than guessing.
    public static func category(forDomain host: String) -> SpendingCategory? {
        let normalized = host.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = domains[normalized] { return exact }

        let parts = normalized.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        let registrable = parts.suffix(2).joined(separator: ".")
        return domains[registrable]
    }

    // MARK: - Physical

    /// Covers both generations of Google's type vocabulary. The older Places API
    /// returned things like `grocery_or_supermarket` and `lodging`; Places API
    /// (New) split those into `grocery_store`, `hotel`, `coffee_shop` and so on,
    /// and a response can still carry either. Unknown types are simply not
    /// matched, so carrying both costs nothing but a few lines.
    private static let placeTypes: [String: SpendingCategory] = [
        "restaurant": .dining,
        "cafe": .dining,
        "coffee_shop": .dining,
        "bar": .dining,
        "bakery": .dining,
        "meal_takeaway": .dining,
        "meal_delivery": .dining,
        "fast_food_restaurant": .dining,
        "sandwich_shop": .dining,
        "pizza_restaurant": .dining,
        "food": .dining,
        "supermarket": .groceries,
        "grocery_or_supermarket": .groceries,
        "grocery_store": .groceries,
        "gas_station": .gas,
        "pharmacy": .drugstores,
        "drugstore": .drugstores,
        "department_store": .departmentStore,
        "clothing_store": .departmentStore,
        "discount_store": .departmentStore,
        "shopping_mall": .departmentStore,
        "hardware_store": .homeImprovement,
        "home_improvement_store": .homeImprovement,
        "home_goods_store": .homeImprovement,
        "airport": .flights,
        "lodging": .hotels,
        "hotel": .hotels,
        "motel": .hotels,
        "resort_hotel": .hotels,
        "travel_agency": .travel,
        "transit_station": .transit,
        "subway_station": .transit,
        "train_station": .transit,
        "light_rail_station": .transit,
        "bus_station": .transit,
        "movie_theater": .entertainment,
        "performing_arts_theater": .entertainment,
        "amusement_park": .entertainment,
        "casino": .entertainment,
        "stadium": .entertainment,
        "night_club": .entertainment
    ]

    /// Every type this map can act on. Handed to the Places API as
    /// `includedTypes` so the twenty results that come back are twenty we can
    /// use, rather than twenty banks and hair salons.
    public static func placeTypeNames(for categories: Set<SpendingCategory>) -> [String] {
        placeTypes
            .filter { categories.contains($0.value) }
            .keys
            .sorted()
    }

    /// Names that a place-type lookup gets wrong. Costco is typed as a
    /// department store or supermarket by most providers, but almost never
    /// codes as a supermarket at the network level, which is what actually
    /// decides the reward.
    private static let nameOverrides: [String: SpendingCategory] = [
        "costco": .warehouseClub,
        "sam's club": .warehouseClub,
        "sams club": .warehouseClub,
        "bj's wholesale": .warehouseClub,
        "bjs wholesale": .warehouseClub
    ]

    public static func category(
        forPlaceType type: String,
        merchantName: String? = nil
    ) -> SpendingCategory? {
        if let name = merchantName?.lowercased() {
            for (needle, category) in nameOverrides where name.contains(needle) {
                return category
            }
        }
        return placeTypes[type.lowercased()]
    }

    /// Google returns several types per place, most specific first.
    public static func category(
        forPlaceTypes types: [String],
        merchantName: String? = nil
    ) -> SpendingCategory? {
        if let name = merchantName?.lowercased() {
            for (needle, category) in nameOverrides where name.contains(needle) {
                return category
            }
        }
        for type in types {
            if let match = placeTypes[type.lowercased()] { return match }
        }
        return nil
    }

    /// Places that hold many businesses behind one set of coordinates. Indoor
    /// GPS cannot tell which unit of a mall or which stand in a food court you
    /// are standing in, so a reminder about one of these names the category and
    /// stops there.
    ///
    /// `point_of_interest` and `establishment` are deliberately **not** here,
    /// though they look like they belong. Google attaches them to very nearly
    /// every place it returns, so treating them as ambiguous would downgrade
    /// every reminder the app ever sent and no business would be named again.
    private static let multiTenantTypes: Set<String> = [
        "shopping_mall",
        "food_court",
        "airport",
        "stadium",
        "amusement_park",
        "convention_center",
        "transit_station",
        "train_station",
        "subway_station",
        "bus_station",
        "light_rail_station",
        "tourist_attraction"
    ]

    /// A place we cannot pin to a single till produces a category-level nudge
    /// rather than the name of a business that might be the wrong one.
    public static func confidence(forPlaceTypes types: [String]) -> MerchantConfidence {
        types.contains { multiTenantTypes.contains($0.lowercased()) } ? .categoryOnly : .exact
    }
}
