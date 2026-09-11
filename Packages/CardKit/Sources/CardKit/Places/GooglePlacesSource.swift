import Foundation

public enum PlacesError: Error, Sendable, Equatable {
    /// No key was built into the app. The app falls back to knowing about no
    /// shops rather than pretending, so this is reported, not swallowed.
    case missingAPIKey
    case server(status: Int, message: String)
    case malformedResponse
}

/// Turns coordinates into named businesses, using Google Places API (New).
///
/// Google rather than Foursquare for one reason: `MerchantCategoryMap` is
/// already written against Google's type vocabulary — `grocery_or_supermarket`,
/// `meal_takeaway`, `gas_station` — and has been since before any of this
/// existed. Foursquare would mean a second category mapping to keep correct,
/// which is the kind of duplication that quietly rots.
///
/// **This is not called when a geofence fires.** It is called when the plan is
/// redrawn, which is roughly once per few hundred metres of travel. By the time
/// somebody walks into a shop, that shop's name and category are already sitting
/// in the registered region, on disk. So the reminder works with no signal, in
/// no time, and costs nothing per arrival — which matters, because an app woken
/// by a geofence has seconds to act and may have no network at all.
public struct GooglePlacesSource: MerchantSource {

    public static let endpoint = URL(string: "https://places.googleapis.com/v1/places:searchNearby")!
    /// Google's own ceilings.
    public static let maximumResults = 20
    public static let maximumIncludedTypes = 50
    public static let maximumRadiusMeters: Double = 50_000

    private let apiKey: String
    private let transport: HTTPTransport
    private let cache: MerchantCacheStore
    private let now: @Sendable () -> Date

    public init(
        apiKey: String,
        transport: HTTPTransport,
        cache: MerchantCacheStore = MerchantCacheStore(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.apiKey = apiKey
        self.transport = transport
        self.cache = cache
        self.now = now
    }

    public var sourceDescription: String { "Google Places" }

    public func merchants(
        near coordinate: GeoCoordinate,
        radiusMeters: Double,
        categories: Set<SpendingCategory>
    ) async throws -> [Merchant] {
        guard !apiKey.isEmpty else { throw PlacesError.missingAPIKey }

        let types = MerchantCategoryMap.placeTypeNames(for: categories)
        // Nothing in the wallet earns a bonus anywhere we could recognise, so
        // there is nothing to ask about. Not an error, just a quiet no.
        guard !types.isEmpty else { return [] }

        let asOf = now()
        if let cached = await cache.merchants(near: coordinate, categories: categories, asOf: asOf) {
            return cached
        }

        let response = try await transport.send(try request(
            near: coordinate,
            radiusMeters: radiusMeters,
            types: types
        ))
        guard response.isSuccess else {
            throw PlacesError.server(
                status: response.statusCode,
                message: Self.message(inErrorBody: response.body)
            )
        }

        let found = try Self.merchants(inBody: response.body)
        await cache.store(found, near: coordinate, categories: categories, at: asOf)
        return found
    }

    // MARK: - The request

    private func request(
        near coordinate: GeoCoordinate,
        radiusMeters: Double,
        types: [String]
    ) throws -> HTTPRequest {
        let payload = SearchNearby(
            includedTypes: Array(types.prefix(Self.maximumIncludedTypes)),
            maxResultCount: Self.maximumResults,
            // Nearest first, because the plan wants the nearest twenty and
            // Google's default ranking is prominence — which would hand back
            // the famous restaurant a mile away over the one next door.
            rankPreference: "DISTANCE",
            locationRestriction: .init(circle: .init(
                center: .init(latitude: coordinate.latitude, longitude: coordinate.longitude),
                radius: min(max(radiusMeters, 1), Self.maximumRadiusMeters)
            ))
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let body = try? encoder.encode(payload) else { throw PlacesError.malformedResponse }

        return HTTPRequest(
            url: Self.endpoint,
            method: "POST",
            headers: [
                "Content-Type": "application/json",
                "X-Goog-Api-Key": apiKey,
                // Places API (New) bills by the fields you ask for, and refuses
                // the request outright without this header. Four fields is
                // everything a geofence needs and nothing more.
                "X-Goog-FieldMask": "places.id,places.displayName,places.types,places.location"
            ],
            body: body
        )
    }

    private struct SearchNearby: Encodable {
        struct Center: Encodable {
            var latitude: Double
            var longitude: Double
        }
        struct Circle: Encodable {
            var center: Center
            var radius: Double
        }
        struct Restriction: Encodable {
            var circle: Circle
        }

        var includedTypes: [String]
        var maxResultCount: Int
        var rankPreference: String
        var locationRestriction: Restriction
    }

    // MARK: - The response

    private struct SearchResult: Decodable {
        struct DisplayName: Decodable {
            var text: String
        }
        struct Location: Decodable {
            var latitude: Double
            var longitude: Double
        }
        struct Place: Decodable {
            var id: String
            var displayName: DisplayName?
            var types: [String]?
            var location: Location?
        }

        var places: [Place]?
    }

    private struct ErrorEnvelope: Decodable {
        struct Payload: Decodable {
            var message: String?
            var status: String?
        }
        var error: Payload
    }

    /// A place with no name, no coordinates, or no type we recognise is dropped
    /// rather than guessed at. A geofence around a business we mis-categorised
    /// produces a reminder that names the wrong card, which is worse than none.
    static func merchants(inBody body: Data) throws -> [Merchant] {
        guard let result = try? JSONDecoder().decode(SearchResult.self, from: body) else {
            throw PlacesError.malformedResponse
        }

        var seen: Set<String> = []
        return (result.places ?? []).compactMap { place -> Merchant? in
            guard let name = place.displayName?.text, !name.isEmpty,
                  let location = place.location,
                  seen.insert(place.id).inserted
            else { return nil }

            return Merchant.from(
                id: place.id,
                name: name,
                coordinate: GeoCoordinate(
                    latitude: location.latitude,
                    longitude: location.longitude
                ),
                placeTypes: place.types ?? []
            )
        }
    }

    static func message(inErrorBody body: Data) -> String {
        guard let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: body) else {
            return "The place lookup was refused and said nothing useful about why."
        }
        return envelope.error.message ?? envelope.error.status ?? "Refused."
    }
}
