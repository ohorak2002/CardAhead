import Foundation

/// Remembers what was nearby, so the Places API is asked as rarely as possible.
///
/// The expensive call is not the one at the till — by then the answer is
/// already in the registered geofence and no network is touched at all. The
/// expensive call is redrawing the plan, which happens every time significant
/// location change says the user has moved a few hundred metres. Somebody
/// walking to work and back crosses the same ground twice a day, every day.
///
/// So lookups are snapped to a grid and kept for a long time. Shops do not
/// move, and one that closed produces a geofence that simply never fires —
/// which costs the user nothing, unlike a lookup on every fix, which costs
/// them battery and costs the developer money.
public struct MerchantCache: Codable, Sendable {

    public struct Entry: Codable, Sendable {
        public var merchants: [Merchant]
        public var fetchedAt: Date
    }

    /// Two fixes inside the same square share an answer. 250m is a city block
    /// or so — close enough that the twenty nearest shops are the same twenty.
    public var gridMeters: Double
    public var timeToLive: TimeInterval
    /// Bounded so a year of commuting does not fill the disk.
    public var maximumEntries: Int

    private var entries: [String: Entry]
    /// Oldest use first. Plain array because it never exceeds `maximumEntries`,
    /// which is small enough that a linear scan is free.
    private var recentlyUsed: [String]

    public init(
        gridMeters: Double = 250,
        timeToLive: TimeInterval = 60 * 60 * 24 * 7,
        maximumEntries: Int = 40
    ) {
        self.gridMeters = gridMeters
        self.timeToLive = timeToLive
        self.maximumEntries = maximumEntries
        self.entries = [:]
        self.recentlyUsed = []
    }

    public var count: Int { entries.count }

    // MARK: - Keys

    /// Snaps a coordinate to the grid, and folds in the categories asked for —
    /// a lookup for a wallet that only earns on dining is not an answer for a
    /// wallet that also earns on petrol.
    public func key(for coordinate: GeoCoordinate, categories: Set<SpendingCategory>) -> String {
        let latitudeStep = gridMeters / 111_194.93
        // Degrees of longitude shrink towards the poles, so the grid has to
        // widen to stay square. Clamped near the poles, where it goes infinite.
        let shrink = max(0.01, cos(coordinate.latitude * .pi / 180))
        let longitudeStep = latitudeStep / shrink

        let latitudeCell = Int((coordinate.latitude / latitudeStep).rounded())
        let longitudeCell = Int((coordinate.longitude / longitudeStep).rounded())
        let categoryKey = categories.map(\.rawValue).sorted().joined(separator: ",")
        return "\(latitudeCell):\(longitudeCell):\(categoryKey)"
    }

    // MARK: - Reading and writing

    public mutating func merchants(
        near coordinate: GeoCoordinate,
        categories: Set<SpendingCategory>,
        asOf date: Date
    ) -> [Merchant]? {
        let key = key(for: coordinate, categories: categories)
        guard let entry = entries[key] else { return nil }
        guard date.timeIntervalSince(entry.fetchedAt) < timeToLive else {
            forget(key)
            return nil
        }
        touch(key)
        return entry.merchants
    }

    public mutating func store(
        _ merchants: [Merchant],
        near coordinate: GeoCoordinate,
        categories: Set<SpendingCategory>,
        at date: Date
    ) {
        let key = key(for: coordinate, categories: categories)
        entries[key] = Entry(merchants: merchants, fetchedAt: date)
        touch(key)

        while entries.count > maximumEntries, let oldest = recentlyUsed.first {
            forget(oldest)
        }
    }

    private mutating func touch(_ key: String) {
        recentlyUsed.removeAll { $0 == key }
        recentlyUsed.append(key)
    }

    private mutating func forget(_ key: String) {
        entries[key] = nil
        recentlyUsed.removeAll { $0 == key }
    }
}

/// The cache with a disk behind it and one writer at a time.
///
/// An actor because `MerchantSource` is `Sendable` and the lookup has to mutate
/// — two significant location changes arriving close together must not both
/// decide the cache was empty and both call the API.
public actor MerchantCacheStore {

    private var cache: MerchantCache
    private let fileURL: URL?

    public init(fileURL: URL? = nil, cache: MerchantCache = MerchantCache()) {
        self.fileURL = fileURL
        self.cache = cache
        if let fileURL, let data = try? Data(contentsOf: fileURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let restored = try? decoder.decode(MerchantCache.self, from: data) {
                self.cache = restored
            }
        }
    }

    public var count: Int { cache.count }

    public func merchants(
        near coordinate: GeoCoordinate,
        categories: Set<SpendingCategory>,
        asOf date: Date
    ) -> [Merchant]? {
        cache.merchants(near: coordinate, categories: categories, asOf: date)
    }

    public func store(
        _ merchants: [Merchant],
        near coordinate: GeoCoordinate,
        categories: Set<SpendingCategory>,
        at date: Date
    ) {
        cache.store(merchants, near: coordinate, categories: categories, at: date)
        persist()
    }

    private func persist() {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(cache) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
