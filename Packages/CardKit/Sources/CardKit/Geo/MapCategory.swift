import Foundation

/// What kind of place something is, as the map's filter bar says it.
///
/// **This is a different axis from `SpendingCategory`, and keeping them apart
/// is the point.** `SpendingCategory` answers "what does a card pay here",
/// which is what the ranking engine needs; `MapCategory` answers "what sort of
/// shop is this", which is what somebody scanning a map is actually filtering
/// on. They overlap but they are not the same list: a pharmacy is its own
/// earning category on several cards and nobody has ever looked at a map
/// thinking "show me drugstores", and a mall is one pin on a map but is not a
/// category any issuer pays on.
///
/// So a place carries both. The filter chips use this; the card recommendation
/// underneath uses the other; and neither has to be bent to serve the other's
/// job.
///
/// `other` is the honest bucket rather than a dustbin: it is everything the
/// place vocabulary below recognises but that does not belong on one of the
/// named shelves — a pharmacy, a bank, a gym, a station. A place whose types
/// mean nothing to us at all still lands here, and still gets a pin, because
/// the map is a browsing surface. What it does *not* get is an invented
/// earning category — `spendingCategory` is simply nil and the row says
/// plainly that no card pays extra there.
public enum MapCategory: String, Codable, CaseIterable, Sendable, Hashable {
    case restaurants
    case gasStations
    case groceries
    case shopping
    case malls
    case entertainment
    case hotels
    case other

    /// Sentence case, matching `SpendingCategory.displayName` — the app does
    /// not Title Case Its Labels.
    public var displayName: String {
        switch self {
        case .restaurants: return "Restaurants"
        case .gasStations: return "Gas stations"
        case .groceries: return "Grocery stores"
        case .shopping: return "Shopping & retail"
        case .malls: return "Malls"
        case .entertainment: return "Entertainment"
        case .hotels: return "Hotels"
        case .other: return "Other"
        }
    }

    /// What fits on a filter chip. "Grocery stores" wraps; "Groceries" does not.
    public var shortName: String {
        switch self {
        case .restaurants: return "Restaurants"
        case .gasStations: return "Gas"
        case .groceries: return "Groceries"
        case .shopping: return "Shopping"
        case .malls: return "Malls"
        case .entertainment: return "Entertainment"
        case .hotels: return "Hotels"
        case .other: return "Other"
        }
    }

    /// The chips the mockup puts on the map itself, in front of the "more
    /// filters" button. The rest live behind it.
    public static let quickFilters: [MapCategory] = [.restaurants, .gasStations, .groceries]

    // MARK: - The place vocabulary

    /// Google Places types, per category.
    ///
    /// **An unrecognised type fails the whole request**, not just its own
    /// results: Places API (New) rejects `includedTypes` it does not know with
    /// `INVALID_ARGUMENT` and returns nothing. So this list is deliberately
    /// conservative — long-established types only, no recent or niche
    /// additions — and `NearbyMapView` surfaces a lookup failure as text on
    /// the screen rather than an empty map, so a bad type here is diagnosable
    /// on a device instead of looking like "nothing nearby".
    ///
    /// Covers both generations of the vocabulary for the same reason
    /// `MerchantCategoryMap` does: a response can still carry either.
    public var placeTypes: [String] {
        switch self {
        case .restaurants:
            return ["restaurant", "cafe", "bakery", "bar", "meal_takeaway", "meal_delivery"]
        case .gasStations:
            return ["gas_station"]
        case .groceries:
            return ["supermarket", "grocery_or_supermarket", "grocery_store", "convenience_store"]
        case .shopping:
            return [
                "book_store", "clothing_store", "department_store", "electronics_store",
                "furniture_store", "hardware_store", "home_goods_store", "jewelry_store",
                "pet_store", "shoe_store", "shopping_center", "store"
            ]
        case .malls:
            return ["shopping_mall"]
        case .entertainment:
            return [
                "amusement_park", "bowling_alley", "casino", "movie_theater",
                "museum", "night_club", "stadium", "tourist_attraction", "zoo"
            ]
        case .hotels:
            return ["hotel", "lodging", "motel", "resort_hotel"]
        case .other:
            return [
                "atm", "bank", "car_rental", "car_repair", "drugstore", "gym",
                "hair_salon", "pharmacy", "post_office", "spa", "transit_station"
            ]
        }
    }

    /// Priority order for resolving a place that matches more than one.
    ///
    /// Google hands back several types per place and the useful one is not
    /// always first. A petrol station is very often also a
    /// `convenience_store`, and a mall is nearly always also a `store` — so
    /// the more specific answer has to win regardless of the order the types
    /// arrived in, which means iterating categories rather than iterating the
    /// place's types.
    ///
    /// **Specific beats generic, which is why `shopping` is last.** Its list
    /// contains `store`, which Google attaches to a chemist, a petrol station
    /// shop and a phone repair counter alike. Every named category — `other`
    /// included, since a pharmacy or a bank is a specific thing and not
    /// "retail" — has to be asked before the bucket holding the catch-all.
    /// This was written the other way round first, and a test caught a
    /// Walgreens filed under "Shopping & retail".
    private static let resolutionOrder: [MapCategory] = [
        .gasStations, .malls, .restaurants, .groceries, .hotels, .entertainment, .other, .shopping
    ]

    /// Which chip a place belongs under. Never nil: a place whose types mean
    /// nothing here is `other`, not a dropped pin.
    public static func matching(placeTypes types: [String]) -> MapCategory {
        let lowered = Set(types.map { $0.lowercased() })
        guard !lowered.isEmpty else { return .other }
        for category in resolutionOrder where !lowered.isDisjoint(with: Set(category.placeTypes)) {
            return category
        }
        return .other
    }

    /// Every type the map knows how to ask for, deduplicated.
    ///
    /// Sent as `includedTypes` even when the filter says "All". The
    /// alternative — omitting the field, which Google reads as "anything" —
    /// sounds more honest but is worse: `searchNearby` returns at most twenty
    /// results, so an untargeted query spends most of that budget on office
    /// suites and residential addresses and hands back a map with four shops
    /// on it.
    public static func placeTypes(for categories: Set<MapCategory>) -> [String] {
        let wanted = categories.isEmpty ? Set(MapCategory.allCases) : categories
        var seen: Set<String> = []
        var ordered: [String] = []
        for category in allCases where wanted.contains(category) {
            for type in category.placeTypes where seen.insert(type).inserted {
                ordered.append(type)
            }
        }
        return ordered.sorted()
    }

    // MARK: - Wayfinding

    /// The benefit shelf this sort of place usually earns under, or nil when
    /// it does not reliably earn anything.
    ///
    /// Only used to borrow a colour and a symbol. The *actual* earning
    /// category of a given place comes from `MerchantCategoryMap`, per place,
    /// off its own types — this is the chip's colour, not a claim about money.
    public var benefitGroup: BenefitGroup? {
        switch self {
        case .restaurants: return .dining
        case .gasStations: return .gas
        case .groceries: return .groceries
        case .shopping, .malls: return .shopping
        case .entertainment: return .entertainment
        case .hotels: return .travel
        case .other: return nil
        }
    }

    /// Distinct per category even where two share a colour: malls and shops
    /// are the same shelf and the same orange, and the symbol is what tells
    /// them apart.
    public var symbolName: String {
        switch self {
        case .restaurants: return "fork.knife"
        case .gasStations: return "fuelpump.fill"
        case .groceries: return "basket.fill"
        case .shopping: return "bag.fill"
        case .malls: return "building.2.fill"
        case .entertainment: return "theatermasks.fill"
        case .hotels: return "bed.double.fill"
        case .other: return "mappin"
        }
    }
}
