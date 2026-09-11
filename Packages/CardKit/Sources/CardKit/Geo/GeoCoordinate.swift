import Foundation

/// A point on the earth, with no Core Location anywhere near it.
///
/// `CardKit` has no CoreLocation dependency on purpose, so everything that
/// decides *which* places to watch stays testable on Linux CI in seconds. The
/// app converts to and from `CLLocationCoordinate2D` at the boundary and
/// nowhere else.
public struct GeoCoordinate: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Great-circle distance in metres.
    ///
    /// Haversine on a sphere of the IUGG mean radius. It is off by up to ~0.5%
    /// against a proper ellipsoid, which is metres over a city and irrelevant
    /// here: this number only ever ranks nearby shops and sizes a geofence
    /// whose radius is 100m and whose real-world accuracy is worse than that.
    public func distance(to other: GeoCoordinate) -> Double {
        let earthRadiusMeters = 6_371_008.8
        let degreesToRadians = Double.pi / 180

        let lat1 = latitude * degreesToRadians
        let lat2 = other.latitude * degreesToRadians
        let deltaLat = (other.latitude - latitude) * degreesToRadians
        let deltaLon = (other.longitude - longitude) * degreesToRadians

        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(max(0, 1 - a)))
        return earthRadiusMeters * c
    }

    public var isValid: Bool {
        latitude >= -90 && latitude <= 90
            && longitude >= -180 && longitude <= 180
            && !(latitude == 0 && longitude == 0)
    }
}
