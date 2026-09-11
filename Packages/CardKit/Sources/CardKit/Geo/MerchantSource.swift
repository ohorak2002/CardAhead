import Foundation

/// Where the list of nearby businesses comes from.
///
/// Deliberately a protocol with a useless default: the real implementation is a
/// paid third-party Places API with a key, a quota and a cache, and none of that
/// belongs in the layer that decides which shops to watch. Region monitoring can
/// therefore be built, reasoned about and tested before a single HTTP request
/// exists.
public protocol MerchantSource: Sendable {
    /// Businesses within `radiusMeters` of the coordinate, already mapped onto
    /// spending categories. Returning fewer than asked for is normal; returning
    /// none is normal in a field.
    func merchants(near coordinate: GeoCoordinate, radiusMeters: Double) async throws -> [Merchant]

    /// Shown in the app's own diagnostics so it is obvious at a glance whether
    /// real data is wired up.
    var sourceDescription: String { get }
}

/// Knows about no shops at all.
///
/// This is what ships until the Places API is wired in, and it is honest about
/// it: with this source installed the geofencing machinery runs end to end and
/// registers exactly zero regions, because it has nowhere to get a shop from.
/// Nothing here invents coordinates to make a demo look alive.
public struct EmptyMerchantSource: MerchantSource {
    public init() {}

    public func merchants(near coordinate: GeoCoordinate, radiusMeters: Double) async throws -> [Merchant] {
        []
    }

    public var sourceDescription: String { "None — no place provider is configured" }
}

/// A fixed list, for tests and for anyone who wants to drive the machinery from
/// a debugger without a network.
public struct StaticMerchantSource: MerchantSource {
    public var all: [Merchant]

    public init(_ all: [Merchant]) {
        self.all = all
    }

    public func merchants(near coordinate: GeoCoordinate, radiusMeters: Double) async throws -> [Merchant] {
        all.filter { $0.coordinate.distance(to: coordinate) <= radiusMeters }
    }

    public var sourceDescription: String { "Fixed list of \(all.count)" }
}
