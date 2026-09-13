import Foundation

/// One pin on the map, which may stand for several shops.
///
/// A high street puts twenty businesses inside a hundred metres. Drawn one pin
/// each, they overlap into a heap, the ones underneath cannot be tapped at
/// all, and the heap does not even tell you how many are in it. So pins that
/// would collide are drawn as one carrying a count, and tapping it zooms in
/// until they come apart.
///
/// **A group of one is not a special case.** Every pin the map draws is a
/// `MapPinGroup`; most of them happen to hold a single shop. That keeps one
/// code path in the view instead of two that have to agree with each other.
public struct MapPinGroup: Identifiable, Sendable, Hashable {

    /// The lowest member id, **not** the first one.
    ///
    /// Deliberate: the first member changes when the sort order does, and an
    /// identity that changes under a re-sort makes SwiftUI tear down and
    /// rebuild every annotation on the map. The lowest id is the same whatever
    /// order the members arrived in.
    public var id: String
    /// The mean of the members' positions. A group of one sits exactly on its
    /// shop; a group of five sits in the middle of them.
    public var coordinate: GeoCoordinate
    /// In the order they were handed in, so the list behind a tap is in the
    /// same order as the list under the map.
    public var results: [MapPlaceResult]

    /// How far apart the members actually are, so a tap can zoom to exactly
    /// the amount that pulls them apart rather than a fixed guess.
    public var latitudeSpread: Double
    public var longitudeSpread: Double

    public init(
        id: String,
        coordinate: GeoCoordinate,
        results: [MapPlaceResult],
        latitudeSpread: Double,
        longitudeSpread: Double
    ) {
        self.id = id
        self.coordinate = coordinate
        self.results = results
        self.latitudeSpread = latitudeSpread
        self.longitudeSpread = longitudeSpread
    }

    public var count: Int { results.count }
    public var isCluster: Bool { results.count > 1 }
    /// The one shop, when there is only one.
    public var single: MapPlaceResult? { results.count == 1 ? results[0] : nil }

    /// True when *any* member is somewhere a card beats its everyday rate.
    /// A cluster is a reason to look closer, and hiding the one good shop
    /// inside it behind a plain pin would defeat the point of the ring.
    public var hasOpportunity: Bool { results.contains(where: \.isOpportunity) }

    /// What colour to draw a cluster: the commonest kind of place in it, ties
    /// broken by `MapCategory`'s own declaration order so the answer is the
    /// same every time rather than whatever the dictionary felt like.
    public var dominantCategory: MapCategory {
        var counts: [MapCategory: Int] = [:]
        for result in results {
            counts[result.place.mapCategory, default: 0] += 1
        }
        return MapCategory.allCases
            .max { left, right in (counts[left] ?? 0) < (counts[right] ?? 0) } ?? .other
    }

    /// The nearest member, which is what a cluster's label says under its
    /// count: "3 places · from 0.2 mi".
    public var nearest: MapPlaceResult? {
        results.min { $0.distanceMeters < $1.distanceMeters }
    }
}

public extension NearbyPlaces {

    /// A pin's own size, in points, including the white ring around it.
    /// Two pins closer together than this on screen are touching.
    static let pinDiameterPoints: Double = 40

    /// Groups results that would overlap on screen.
    ///
    /// `separationDegrees` is a *latitude* distance, because a degree of
    /// latitude is the same length everywhere and a degree of longitude is
    /// not. Longitude is compared against the same number widened by
    /// `1 / cos(latitude)`, so the catchment is a circle on the ground rather
    /// than an ellipse that gets fatter towards the poles — the same
    /// correction `MerchantCache`'s grid makes, for the same reason.
    ///
    /// Greedy, single pass, in the order given. That is not the tightest
    /// clustering available and it does not need to be: it is deterministic,
    /// it is O(n × groups) over at most twenty pins, and a k-means that
    /// reshuffled its groups between two identical refreshes would make the
    /// map twitch for no visible reason.
    static func pinGroups(
        for results: [MapPlaceResult],
        separationDegrees: Double,
        referenceLatitude: Double
    ) -> [MapPinGroup] {
        guard separationDegrees > 0 else {
            return results.map { single($0) }
        }

        let shrink = max(0.01, cos(referenceLatitude * .pi / 180))
        let longitudeSeparation = separationDegrees / shrink

        var groups: [[MapPlaceResult]] = []
        var centroids: [GeoCoordinate] = []

        for result in results {
            let place = result.place.coordinate
            var joined = false
            for index in groups.indices {
                let centroid = centroids[index]
                guard abs(place.latitude - centroid.latitude) <= separationDegrees,
                      abs(place.longitude - centroid.longitude) <= longitudeSeparation
                else { continue }
                groups[index].append(result)
                centroids[index] = mean(of: groups[index])
                joined = true
                break
            }
            if !joined {
                groups.append([result])
                centroids.append(place)
            }
        }

        return zip(groups, centroids).map { members, centroid in
            let latitudes = members.map(\.place.coordinate.latitude)
            let longitudes = members.map(\.place.coordinate.longitude)
            return MapPinGroup(
                id: members.map(\.id).min() ?? "",
                coordinate: centroid,
                results: members,
                latitudeSpread: (latitudes.max() ?? 0) - (latitudes.min() ?? 0),
                longitudeSpread: (longitudes.max() ?? 0) - (longitudes.min() ?? 0)
            )
        }
    }

    private static func single(_ result: MapPlaceResult) -> MapPinGroup {
        MapPinGroup(
            id: result.id,
            coordinate: result.place.coordinate,
            results: [result],
            latitudeSpread: 0,
            longitudeSpread: 0
        )
    }

    private static func mean(of results: [MapPlaceResult]) -> GeoCoordinate {
        let count = Double(results.count)
        guard count > 0 else { return GeoCoordinate(latitude: 0, longitude: 0) }
        return GeoCoordinate(
            latitude: results.reduce(0) { $0 + $1.place.coordinate.latitude } / count,
            longitude: results.reduce(0) { $0 + $1.place.coordinate.longitude } / count
        )
    }
}

public extension RegionPlan {
    /// The place ids currently sitting in a geofence.
    ///
    /// This is what lets the map say which shops the app is *actually*
    /// watching, rather than leaving the reminders to arrive out of nowhere.
    /// The ids line up because both halves of the app ask the same place
    /// provider and keep its id — see `Merchant.id` and `MapPlace.id`. If a
    /// second provider is ever added, this is the join that breaks, and it
    /// will break silently by matching nothing.
    var watchedPlaceIDs: Set<String> {
        Set(regions.map(\.merchant.id))
    }
}
