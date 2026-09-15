import Foundation

/// Where the map gets the shops it draws.
///
/// **Separate from `MerchantSource` on purpose.** `MerchantSource` answers one
/// question — "which shops near here could earn something, so I can geofence
/// them" — and its answer is shaped by that: at most twenty, filtered to the
/// wallet's earning categories, cached for a week because it is asked every
/// few hundred metres of travel whether anybody is looking or not.
///
/// The map asks a different question. It is a foreground surface somebody is
/// looking at, it wants places the wallet earns nothing at, it wants a search
/// box, and it wants a shop's phone number and opening hours — none of which a
/// geofence has any use for. Folding both into one protocol would mean every
/// geofence redraw paying for fields it throws away.
///
/// They share the vocabulary (`MerchantCategoryMap`), the HTTP seam
/// (`HTTPTransport`) and the key. They do not share a request.
public protocol PlaceSearchSource: Sendable {

    /// Places of the given kinds within `radiusMeters`. Fewer than asked for
    /// is normal; none is normal in a field.
    func places(
        near coordinate: GeoCoordinate,
        radiusMeters: Double,
        categories: Set<MapCategory>
    ) async throws -> [MapPlace]

    /// What the search box does. `query` is whatever the user typed — a shop
    /// name, a chain, or a kind of place.
    func places(
        matching query: String,
        near coordinate: GeoCoordinate,
        radiusMeters: Double
    ) async throws -> [MapPlace]

    /// The expensive one: rating, hours, phone, website for a single place.
    /// Called when somebody opens a place, never for a list.
    func details(forPlaceID id: String) async throws -> MapPlace

    /// Where to get a photograph's bytes, at the size this use needs, or nil
    /// when this source has no photographs to offer.
    ///
    /// **A default of nil, rather than a requirement.** Two of the three
    /// sources here have no images by design and a third — whatever replaces
    /// Google if that day comes — might not either. A screen that reads a nil
    /// here draws its fallback, which is the same thing it does for a place
    /// Google happens to have no photo of, so the path is exercised either
    /// way rather than being a branch nobody has seen.
    func photoRequest(for photo: PlacePhoto, use: PlacePhotoUse) -> HTTPRequest?

    /// Shown in the app's own diagnostics, so whether real data is wired up is
    /// answerable without a debugger.
    var sourceDescription: String { get }
}

public extension PlaceSearchSource {
    func photoRequest(for photo: PlacePhoto, use: PlacePhotoUse) -> HTTPRequest? { nil }
}

/// Knows about no places at all.
///
/// Installed when no Places key was built into the app, and honest about it:
/// the map runs, shows the user's own location, and says in plain words that
/// it has nowhere to get shops from. It does not invent a single pin — the
/// same rule `EmptyMerchantSource` follows, for the same reason.
public struct EmptyPlaceSearchSource: PlaceSearchSource {
    public init() {}

    public func places(
        near coordinate: GeoCoordinate,
        radiusMeters: Double,
        categories: Set<MapCategory>
    ) async throws -> [MapPlace] { [] }

    public func places(
        matching query: String,
        near coordinate: GeoCoordinate,
        radiusMeters: Double
    ) async throws -> [MapPlace] { [] }

    public func details(forPlaceID id: String) async throws -> MapPlace {
        throw PlacesError.missingAPIKey
    }

    public var sourceDescription: String { "Nothing — no place provider is configured" }
}

/// A fixed list, for tests and for the seeded screenshot run.
public struct StaticPlaceSearchSource: PlaceSearchSource {
    public var all: [MapPlace]

    public init(_ all: [MapPlace]) {
        self.all = all
    }

    public func places(
        near coordinate: GeoCoordinate,
        radiusMeters: Double,
        categories: Set<MapCategory>
    ) async throws -> [MapPlace] {
        let wanted = categories.isEmpty ? Set(MapCategory.allCases) : categories
        return all.filter {
            wanted.contains($0.mapCategory) && $0.coordinate.distance(to: coordinate) <= radiusMeters
        }
    }

    public func places(
        matching query: String,
        near coordinate: GeoCoordinate,
        radiusMeters: Double
    ) async throws -> [MapPlace] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        return all.filter { place in
            guard place.coordinate.distance(to: coordinate) <= radiusMeters else { return false }
            return place.name.lowercased().contains(needle)
                || place.mapCategory.displayName.lowercased().contains(needle)
                || (place.typeDescription?.lowercased().contains(needle) ?? false)
        }
    }

    public func details(forPlaceID id: String) async throws -> MapPlace {
        guard let found = all.first(where: { $0.id == id }) else {
            throw PlacesError.malformedResponse
        }
        return found
    }

    public var sourceDescription: String { "Fixed list of \(all.count)" }
}

// MARK: - Cache

/// What the map has already looked up.
///
/// **In memory only, unlike `MerchantCache`, and that is deliberate.** The
/// geofence cache is written to disk because the lookups it saves happen while
/// nobody is watching — every few hundred metres of a commute, for weeks. The
/// map's lookups only happen while somebody is holding the phone and looking
/// at it, so a cache that dies with the process costs one request on the next
/// launch and saves the disk a file that would go stale unseen.
///
/// The grid is the same idea as `MerchantCache`'s and for the same reason: two
/// fixes a few paces apart are the same question.
public actor MapPlaceCache {

    private struct Entry {
        var places: [MapPlace]
        var fetchedAt: Date
    }

    private var entries: [String: Entry] = [:]
    private var recentlyUsed: [String] = []
    private var detailEntries: [String: Entry] = [:]

    private let gridMeters: Double
    private let timeToLive: TimeInterval
    private let detailTimeToLive: TimeInterval
    private let maximumEntries: Int

    public init(
        gridMeters: Double = 250,
        timeToLive: TimeInterval = 60 * 60,
        detailTimeToLive: TimeInterval = 60 * 60 * 24,
        maximumEntries: Int = 40
    ) {
        self.gridMeters = gridMeters
        self.timeToLive = timeToLive
        self.detailTimeToLive = detailTimeToLive
        self.maximumEntries = maximumEntries
    }

    /// Snaps to a grid square, and folds in everything else that changes the
    /// answer. The radius is part of the key because a one-mile question and a
    /// ten-mile question asked from the same doorstep are different questions.
    public func key(
        for coordinate: GeoCoordinate,
        categories: Set<MapCategory>,
        radiusMeters: Double,
        query: String?
    ) -> String {
        let latitudeStep = gridMeters / 111_194.93
        let shrink = max(0.01, cos(coordinate.latitude * .pi / 180))
        let longitudeStep = latitudeStep / shrink

        let latitudeCell = Int((coordinate.latitude / latitudeStep).rounded())
        let longitudeCell = Int((coordinate.longitude / longitudeStep).rounded())
        let categoryKey = categories.isEmpty
            ? "all"
            : categories.map(\.rawValue).sorted().joined(separator: ",")
        let radiusKey = Int(radiusMeters.rounded())
        let queryKey = (query ?? "").lowercased()
        return "\(latitudeCell):\(longitudeCell):\(radiusKey):\(categoryKey):\(queryKey)"
    }

    public func places(forKey key: String, asOf date: Date) -> [MapPlace]? {
        guard let entry = entries[key] else { return nil }
        guard date.timeIntervalSince(entry.fetchedAt) < timeToLive else {
            forget(key)
            return nil
        }
        touch(key)
        return entry.places
    }

    public func store(_ places: [MapPlace], forKey key: String, at date: Date) {
        entries[key] = Entry(places: places, fetchedAt: date)
        touch(key)
        while entries.count > maximumEntries, let oldest = recentlyUsed.first {
            forget(oldest)
        }
    }

    public func detail(forPlaceID id: String, asOf date: Date) -> MapPlace? {
        guard let entry = detailEntries[id], let place = entry.places.first else { return nil }
        guard date.timeIntervalSince(entry.fetchedAt) < detailTimeToLive else {
            detailEntries[id] = nil
            return nil
        }
        return place
    }

    public func storeDetail(_ place: MapPlace, at date: Date) {
        detailEntries[place.id] = Entry(places: [place], fetchedAt: date)
        // A day of browsing should not grow without a ceiling either. Details
        // are small, so the bound is generous rather than tight.
        if detailEntries.count > maximumEntries * 4 {
            detailEntries.removeAll()
        }
    }

    private func touch(_ key: String) {
        recentlyUsed.removeAll { $0 == key }
        recentlyUsed.append(key)
    }

    private func forget(_ key: String) {
        entries[key] = nil
        recentlyUsed.removeAll { $0 == key }
    }

    public var count: Int { entries.count }
}
