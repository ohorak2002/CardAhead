import Foundation

/// Where the list of nearby businesses comes from.
///
/// The categories are part of the question, not a filter applied afterwards.
/// A provider hands back at most twenty results; asking it for "anything" and
/// discarding nineteen banks and hairdressers would leave one usable geofence
/// out of the twenty iOS allows.
public protocol MerchantSource: Sendable {
    /// Businesses within `radiusMeters` of the coordinate that fall into one of
    /// `categories`, already mapped. Returning fewer than asked for is normal;
    /// returning none is normal in a field.
    func merchants(
        near coordinate: GeoCoordinate,
        radiusMeters: Double,
        categories: Set<SpendingCategory>
    ) async throws -> [Merchant]

    /// Shown in the app's own diagnostics so it is obvious at a glance whether
    /// real data is wired up.
    var sourceDescription: String { get }
}

/// Knows about no shops at all.
///
/// Installed when no Places API key was built into the app. It is honest about
/// it: the geofencing machinery runs end to end and registers exactly zero
/// regions, because it has nowhere to get a shop from. Nothing here invents
/// coordinates to make a demo look alive.
public struct EmptyMerchantSource: MerchantSource {
    public init() {}

    public func merchants(
        near coordinate: GeoCoordinate,
        radiusMeters: Double,
        categories: Set<SpendingCategory>
    ) async throws -> [Merchant] {
        []
    }

    public var sourceDescription: String { "Nothing — no place provider is configured" }
}

/// A fixed list, for tests and for anyone who wants to drive the machinery from
/// a debugger without a network.
public struct StaticMerchantSource: MerchantSource {
    public var all: [Merchant]

    public init(_ all: [Merchant]) {
        self.all = all
    }

    public func merchants(
        near coordinate: GeoCoordinate,
        radiusMeters: Double,
        categories: Set<SpendingCategory>
    ) async throws -> [Merchant] {
        all.filter {
            categories.contains($0.category) && $0.coordinate.distance(to: coordinate) <= radiusMeters
        }
    }

    public var sourceDescription: String { "Fixed list of \(all.count)" }
}
