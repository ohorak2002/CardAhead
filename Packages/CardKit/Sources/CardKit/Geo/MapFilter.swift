import Foundation

/// How far out the map looks.
///
/// Miles rather than metres because every label in this app is written for a
/// person in the United States, and the five steps are the mockup's. Stored as
/// a case rather than a number so a slider cannot land on 2.7 miles and a
/// persisted filter written by an older build still decodes.
public enum MapDistance: String, Codable, CaseIterable, Sendable, Hashable {
    case halfMile
    case oneMile
    case threeMiles
    case fiveMiles
    case tenMiles

    public var miles: Double {
        switch self {
        case .halfMile: return 0.5
        case .oneMile: return 1
        case .threeMiles: return 3
        case .fiveMiles: return 5
        case .tenMiles: return 10
        }
    }

    public var meters: Double { miles * 1_609.344 }

    public var displayName: String {
        switch self {
        case .halfMile: return "0.5 miles"
        case .oneMile: return "1 mile"
        case .threeMiles: return "3 miles"
        case .fiveMiles: return "5 miles"
        case .tenMiles: return "10 miles"
        }
    }

    /// What fits on the chip next to the category chips.
    public var shortName: String {
        switch self {
        case .halfMile: return "0.5 mi"
        case .oneMile: return "1 mi"
        case .threeMiles: return "3 mi"
        case .fiveMiles: return "5 mi"
        case .tenMiles: return "10 mi"
        }
    }

    /// Three miles: far enough to cover the errands somebody would actually
    /// drive to, close enough that twenty results are all reachable.
    public static let standard: MapDistance = .threeMiles
}

/// The order the results list is in.
public enum MapSort: String, Codable, CaseIterable, Sendable, Hashable {
    case nearest
    case bestReward
    case topRated

    public var displayName: String {
        switch self {
        case .nearest: return "Nearest"
        case .bestReward: return "Best reward"
        case .topRated: return "Highest rated"
        }
    }
}

/// What the map is currently showing.
///
/// Persisted, so somebody who only ever wants to see petrol stations does not
/// re-pick that every time the app opens.
public struct MapFilter: Codable, Hashable, Sendable {

    /// **Empty means every category**, not none. The distinction matters
    /// because "All" is a real, default state a person picks deliberately, and
    /// modelling it as "all eight ticked" means a filter written today breaks
    /// the first time a ninth category is added — everybody's saved "All"
    /// would silently become "all except the new one".
    public enum Selection: String, Codable, Sendable { case all, none, custom }
    public private(set) var selection: Selection
    public var categories: Set<MapCategory>
    public var distance: MapDistance
    public var sort: MapSort

    public init(
        categories: Set<MapCategory> = [],
        distance: MapDistance = .standard,
        sort: MapSort = .nearest
    ) {
        self.selection = categories.isEmpty ? .all : .custom
        self.categories = categories
        self.distance = distance
        self.sort = sort
    }

    public static let standard = MapFilter()

    private enum CodingKeys: String, CodingKey { case selection, categories, distance, sort }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        categories = try c.decode(Set<MapCategory>.self, forKey: .categories)
        distance = try c.decode(MapDistance.self, forKey: .distance)
        sort = try c.decode(MapSort.self, forKey: .sort)
        // Version 1 used an empty set (and a full set) to mean All.
        selection = try c.decodeIfPresent(Selection.self, forKey: .selection)
            ?? (categories.isEmpty || categories.count == MapCategory.allCases.count ? .all : .custom)
        if selection != .custom { categories = [] }
        if selection == .custom && categories.isEmpty { selection = .none }
    }

    public var isShowingEverything: Bool { selection == .all }
    public var isShowingNothing: Bool { selection == .none }
    public var effectiveCategories: Set<MapCategory> {
        selection == .all ? Set(MapCategory.allCases) : (selection == .none ? [] : categories)
    }
    public func includes(_ category: MapCategory) -> Bool { effectiveCategories.contains(category) }
    public mutating func toggle(_ category: MapCategory) {
        if selection != .custom { categories = [] }
        if categories.contains(category) { categories.remove(category) }
        else { categories.insert(category) }
        selection = categories.isEmpty ? .none : .custom
    }
    public mutating func showEverything() { selection = .all; categories = [] }
    public mutating func showNothing() { selection = .none; categories = [] }
    public mutating func toggleAll() {
        if isShowingEverything { showNothing() } else { showEverything() }
    }
    public mutating func showOnly(_ category: MapCategory) { selection = .custom; categories = [category] }

    /// What to ask the place provider for.
    public var requestedPlaceTypes: [String] {
        MapCategory.placeTypes(for: effectiveCategories)
    }

    /// A line under the map saying what is being shown, for the times when
    /// the chips have scrolled out of view.
    public var summary: String {
        if isShowingNothing { return "Select a category to see nearby places" }
        if isShowingEverything { return "Everything within \(distance.displayName)" }
        let names = MapCategory.allCases
            .filter { categories.contains($0) }
            .map(\.displayName)
        let subject: String
        switch names.count {
        case 1: subject = names[0]
        case 2: subject = "\(names[0]) and \(names[1])"
        default: subject = "\(names.count) kinds of place"
        }
        return "\(subject) within \(distance.displayName)"
    }
}

// MARK: - Turning places into a list

/// Filtering, measuring and ranking the map's results.
///
/// Pure and synchronous, and here rather than in the view for the reason the
/// rest of `CardKit` exists: everything that could be *wrong* — which places
/// are in range, which card wins at each, what order they come in — is
/// testable on Linux in seconds, and what is left in the app is a map view
/// drawing pins.
public enum NearbyPlaces {

    /// `ignoringDistance` is for one caller: the list of shops that already
    /// have a geofence. A geofence four miles out is still one of the twenty
    /// iOS is watching, and dropping it because the map's radius happens to be
    /// set to three would make the count on screen disagree with the thing it
    /// is counting. Every other caller wants the radius applied.
    public static func results(
        from places: [MapPlace],
        near center: GeoCoordinate,
        cards: [Card],
        filter: MapFilter = .standard,
        ignoringDistance: Bool = false,
        engine: RecommendationEngine = RecommendationEngine(),
        asOf date: Date = Date()
    ) -> [MapPlaceResult] {

        let radius = ignoringDistance ? Double.greatestFiniteMagnitude : filter.distance.meters
        var seen: Set<String> = []

        let measured: [MapPlaceResult] = places.compactMap { place in
            guard place.coordinate.isValid else { return nil }
            guard filter.includes(place.mapCategory) else { return nil }
            let distance = center.distance(to: place.coordinate)
            guard distance <= radius else { return nil }
            guard seen.insert(place.id).inserted else { return nil }

            var recommendation: Recommendation?
            if !cards.isEmpty, let context = place.purchaseContext(asOf: date) {
                recommendation = engine.recommend(from: cards, in: context)
            }
            return MapPlaceResult(
                place: place,
                distanceMeters: distance,
                recommendation: recommendation
            )
        }

        return measured.sorted { isBefore($0, $1, by: filter.sort) }
    }

    /// Every comparison falls through to distance and then to id, so the same
    /// input always produces the same order. A list that reshuffles under the
    /// user's thumb between two identical refreshes is the kind of bug nobody
    /// can reproduce on purpose.
    private static func isBefore(_ lhs: MapPlaceResult, _ rhs: MapPlaceResult, by sort: MapSort) -> Bool {
        switch sort {
        case .nearest:
            break

        case .bestReward:
            let left = lhs.recommendation?.best.total ?? -.greatestFiniteMagnitude
            let right = rhs.recommendation?.best.total ?? -.greatestFiniteMagnitude
            if left != right { return left > right }

        case .topRated:
            // Unrated places go last rather than being treated as zero-star,
            // which would rank a shop nobody has reviewed below a bad one.
            let left = lhs.place.rating
            let right = rhs.place.rating
            if left != right {
                guard let left else { return false }
                guard let right else { return true }
                return left > right
            }
        }

        if lhs.distanceMeters != rhs.distanceMeters { return lhs.distanceMeters < rhs.distanceMeters }
        return lhs.place.id < rhs.place.id
    }

    /// How many nearby places pay more than the everyday rate. The number the
    /// Home banner says out loud, so it is counted here once rather than
    /// recomputed by whoever needs it.
    public static func opportunityCount(in results: [MapPlaceResult]) -> Int {
        results.filter(\.isOpportunity).count
    }

    /// Results grouped under their filter chip, for the "Restaurants (24)"
    /// header the list carries when one category is selected.
    public static func counts(in results: [MapPlaceResult]) -> [MapCategory: Int] {
        results.reduce(into: [:]) { counts, result in
            counts[result.place.mapCategory, default: 0] += 1
        }
    }
}
