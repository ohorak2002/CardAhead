import Foundation

/// One geofence we have asked iOS to watch.
public struct MonitoredRegion: Identifiable, Codable, Hashable, Sendable {
    /// Doubles as the `CLRegion` identifier, so an entry event that arrives
    /// after iOS relaunches the app can be matched back to a merchant.
    public var id: String
    public var merchant: Merchant
    public var radiusMeters: Double
    /// Distance from the anchor the plan was made at. Only used for ordering
    /// and for deciding when the plan has gone stale — never re-read as a
    /// live distance, because the user has moved since.
    public var distanceMeters: Double

    public init(id: String, merchant: Merchant, radiusMeters: Double, distanceMeters: Double) {
        self.id = id
        self.merchant = merchant
        self.radiusMeters = radiusMeters
        self.distanceMeters = distanceMeters
    }
}

/// The set of geofences currently registered, and where the user was standing
/// when we chose them.
public struct RegionPlan: Codable, Hashable, Sendable {
    public var anchor: GeoCoordinate
    /// Nearest first.
    public var regions: [MonitoredRegion]
    public var madeAt: Date

    public init(anchor: GeoCoordinate, regions: [MonitoredRegion], madeAt: Date) {
        self.anchor = anchor
        self.regions = regions
        self.madeAt = madeAt
    }

    public func region(withID id: String) -> MonitoredRegion? {
        regions.first { $0.id == id }
    }

    /// How far out the plan reaches. Empty plans reach nowhere.
    public var farthestDistanceMeters: Double {
        regions.last?.distanceMeters ?? 0
    }
}

/// Chooses which twenty places to watch.
///
/// Twenty is not a preference, it is iOS's hard ceiling: an app may monitor at
/// most 20 `CLCircularRegion`s at once, and registering a 21st silently fails.
/// So the whole job is picking the right twenty and swapping them out as the
/// user moves.
///
/// Pure and synchronous — no Core Location, no network, no clock of its own.
public struct RegionPlanner: Sendable {

    /// Apple's per-app limit on simultaneously monitored regions.
    public static let systemRegionLimit = 20

    public var limit: Int
    /// 100m is the usual compromise: tight enough that a shop across the road
    /// is a different region, loose enough that iOS's own location fix (often
    /// 50-65m in a built-up street) still lands inside it.
    public var radiusMeters: Double
    /// Moving this far from the anchor is enough on its own to redraw the plan.
    public var refreshDistanceMeters: Double
    /// Even standing still, a plan this old gets rebuilt — shops open and close,
    /// and a wallet that gained a card wants different categories watched.
    public var maximumPlanAge: TimeInterval

    public init(
        limit: Int = RegionPlanner.systemRegionLimit,
        radiusMeters: Double = 100,
        refreshDistanceMeters: Double = 3_000,
        maximumPlanAge: TimeInterval = 60 * 60 * 24
    ) {
        self.limit = min(limit, Self.systemRegionLimit)
        self.radiusMeters = radiusMeters
        self.refreshDistanceMeters = refreshDistanceMeters
        self.maximumPlanAge = maximumPlanAge
    }

    // MARK: - Relevance

    /// The categories worth waking the user up for: the ones where some card in
    /// the wallet pays more than its own base rate, including this quarter's
    /// rotating bonus.
    ///
    /// A wallet of nothing but flat-rate cards produces an empty set, and that
    /// is the right answer rather than a bug. If every card earns the same rate
    /// everywhere, there is no shop where walking in changes which card to pull
    /// out, so there is nothing to say and no reason to spend the user's
    /// battery finding out where they are.
    public func relevantCategories(in cards: [Card], asOf date: Date = Date()) -> Set<SpendingCategory> {
        var categories: Set<SpendingCategory> = []
        for card in cards {
            categories.formUnion(card.bonusCategories(asOf: date))
        }
        categories.remove(.base)
        return categories
    }

    /// Whether a merchant is worth a geofence for this wallet.
    public func isRelevant(_ merchant: Merchant, to categories: Set<SpendingCategory>) -> Bool {
        categories.contains(merchant.category)
    }

    // MARK: - Planning

    /// The nearest `limit` relevant merchants to `anchor`, nearest first.
    ///
    /// Ties are broken on merchant id so the same input always produces the same
    /// plan — otherwise a refresh that changed nothing would still churn twenty
    /// registrations.
    public func plan(
        around anchor: GeoCoordinate,
        merchants: [Merchant],
        cards: [Card],
        asOf date: Date = Date()
    ) -> RegionPlan {
        let categories = relevantCategories(in: cards, asOf: date)

        let candidates = merchants
            .filter { $0.coordinate.isValid && isRelevant($0, to: categories) }
            .map { (merchant: $0, distance: anchor.distance(to: $0.coordinate)) }
            .sorted { left, right in
                if left.distance != right.distance { return left.distance < right.distance }
                return left.merchant.id < right.merchant.id
            }

        var seen: Set<String> = []
        var regions: [MonitoredRegion] = []
        for candidate in candidates {
            guard seen.insert(candidate.merchant.id).inserted else { continue }
            regions.append(MonitoredRegion(
                id: Self.regionID(for: candidate.merchant),
                merchant: candidate.merchant,
                radiusMeters: radiusMeters,
                distanceMeters: candidate.distance
            ))
            if regions.count == limit { break }
        }

        return RegionPlan(anchor: anchor, regions: regions, madeAt: date)
    }

    /// Identifier handed to `CLCircularRegion`. Prefixed so a region belonging
    /// to this feature is distinguishable from anything else the app might one
    /// day monitor, and from regions left over by an older build.
    public static func regionID(for merchant: Merchant) -> String {
        "merchant.\(merchant.id)"
    }

    public static func isOurs(regionID: String) -> Bool {
        regionID.hasPrefix("merchant.")
    }

    // MARK: - Staying current

    /// Whether the twenty we are watching are still the right twenty.
    ///
    /// Significant location changes arrive roughly every 500m of real movement,
    /// so this is asked often and must say no most of the time.
    public func needsRefresh(_ plan: RegionPlan?, at coordinate: GeoCoordinate, asOf date: Date = Date()) -> Bool {
        guard let plan else { return true }
        guard coordinate.isValid else { return false }

        if date.timeIntervalSince(plan.madeAt) >= maximumPlanAge { return true }

        let moved = plan.anchor.distance(to: coordinate)
        if moved >= refreshDistanceMeters { return true }

        // In a dense high street the twenty nearest shops can all sit within a
        // few hundred metres. Walking half that far is enough for the set
        // picked from here to differ from the set picked back there.
        let reach = plan.farthestDistanceMeters
        if reach > 0, moved >= reach / 2 { return true }

        // An empty plan means nothing relevant was nearby. Any real movement is
        // worth another look rather than waiting out the full refresh distance.
        if plan.regions.isEmpty, moved > 0 { return true }

        return false
    }
}
