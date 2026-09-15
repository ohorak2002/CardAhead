import Foundation

/// The map's half of the Google Places integration.
///
/// Three calls, all against Places API (New), and each one costs money, so
/// what each asks for is a deliberate decision rather than "everything":
///
/// - **Nearby search** draws the pins. Its field mask is
///   `searchFieldMask` below — id, name, types, location, Google's own words
///   for the type, and the star rating. The rating is the one field here that
///   is *not* free: it moves the request from the Essentials SKU to Pro. It is
///   in because the list shows stars and can sort on them, and because paying
///   once for twenty ratings is far cheaper than a details call per row. If
///   that bill ever matters more than the stars do, take the two rating
///   fields out of this mask and the "Highest rated" sort with them.
/// - **Text search** backs the search box, with the same mask.
/// - **Place details** is asked for exactly one place, only when somebody
///   opens it, and is the only call that pays for hours, phone and website.
///
/// Everything is cached (`MapPlaceCache`) so panning back to where you just
/// were costs nothing.
///
/// **This is not on the geofence path.** `GooglePlacesSource` is, it keeps its
/// own lean four-field mask and its own week-long disk cache, and nothing here
/// changes what an arrival costs. See its doc comment.
public struct GooglePlaceSearchSource: PlaceSearchSource {

    public static let nearbyEndpoint = URL(string: "https://places.googleapis.com/v1/places:searchNearby")!
    public static let textEndpoint = URL(string: "https://places.googleapis.com/v1/places:searchText")!
    public static let detailsEndpoint = URL(string: "https://places.googleapis.com/v1/places")!

    /// Google's own ceiling on both searches.
    public static let maximumResults = 20
    public static let maximumIncludedTypes = 50
    public static let maximumRadiusMeters: Double = 50_000

    /// What a list row needs and nothing else. See the SKU note above.
    public static let searchFieldMask = [
        "places.id",
        "places.displayName",
        "places.types",
        "places.location",
        "places.primaryTypeDisplayName",
        "places.rating",
        "places.userRatingCount",
        // **Costs nothing extra here, and that is worth knowing rather than
        // assuming.** Field masks are billed by tier, not by field, and the
        // whole request is already at the tier `places.rating` puts it in;
        // `places.photos` sits below that. What *is* billed per use is
        // fetching the image bytes, which is a separate SKU and a separate
        // request the app only makes for a photo somebody is looking at.
        // See `docs/places-api.md`.
        "places.photos"
    ].joined(separator: ",")

    /// The detail screen's fields. No `places.` prefix: a details request
    /// returns one place rather than a list, and a mask written for the list
    /// endpoint is rejected outright here.
    public static let detailFieldMask = [
        "id",
        "displayName",
        "types",
        "location",
        "primaryTypeDisplayName",
        "formattedAddress",
        "rating",
        "userRatingCount",
        "nationalPhoneNumber",
        "websiteUri",
        "regularOpeningHours",
        "photos"
    ].joined(separator: ",")

    /// Where image bytes come from. The photo's own resource name is appended
    /// to this, then `/media` — see `photoRequest(for:use:)`.
    public static let photoEndpoint = URL(string: "https://places.googleapis.com/v1")!

    private let apiKey: String
    private let transport: HTTPTransport
    private let cache: MapPlaceCache
    private let now: @Sendable () -> Date

    public init(
        apiKey: String,
        transport: HTTPTransport,
        cache: MapPlaceCache = MapPlaceCache(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.apiKey = apiKey
        self.transport = transport
        self.cache = cache
        self.now = now
    }

    public var sourceDescription: String { "Google Places" }

    // MARK: - Nearby

    public func places(
        near coordinate: GeoCoordinate,
        radiusMeters: Double,
        categories: Set<MapCategory>
    ) async throws -> [MapPlace] {
        guard !apiKey.isEmpty else { throw PlacesError.missingAPIKey }

        let asOf = now()
        let key = await cache.key(
            for: coordinate,
            categories: categories,
            radiusMeters: radiusMeters,
            query: nil
        )
        if let cached = await cache.places(forKey: key, asOf: asOf) { return cached }

        let types = MapCategory.placeTypes(for: categories)
        let payload = SearchNearby(
            includedTypes: Array(types.prefix(Self.maximumIncludedTypes)),
            maxResultCount: Self.maximumResults,
            // Nearest first. Google's default is prominence, which would put
            // the famous restaurant across town above the one on this corner —
            // wrong for a map whose whole subject is what is near you.
            rankPreference: "DISTANCE",
            locationRestriction: .init(circle: .init(
                center: .init(latitude: coordinate.latitude, longitude: coordinate.longitude),
                radius: clamped(radiusMeters)
            ))
        )

        let found = try await send(
            payload,
            to: Self.nearbyEndpoint,
            fieldMask: Self.searchFieldMask
        )
        await cache.store(found, forKey: key, at: asOf)
        return found
    }

    // MARK: - Search

    public func places(
        matching query: String,
        near coordinate: GeoCoordinate,
        radiusMeters: Double
    ) async throws -> [MapPlace] {
        guard !apiKey.isEmpty else { throw PlacesError.missingAPIKey }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let asOf = now()
        let key = await cache.key(
            for: coordinate,
            categories: [],
            radiusMeters: radiusMeters,
            query: trimmed
        )
        if let cached = await cache.places(forKey: key, asOf: asOf) { return cached }

        // A *bias*, not a restriction: somebody typing a chain name wants the
        // nearest branch, and refusing to look past the current radius would
        // answer "no results" for a shop half a mile outside it.
        let payload = SearchText(
            textQuery: trimmed,
            maxResultCount: Self.maximumResults,
            locationBias: .init(circle: .init(
                center: .init(latitude: coordinate.latitude, longitude: coordinate.longitude),
                radius: clamped(radiusMeters)
            ))
        )

        let found = try await send(
            payload,
            to: Self.textEndpoint,
            fieldMask: Self.searchFieldMask
        )
        await cache.store(found, forKey: key, at: asOf)
        return found
    }

    // MARK: - Details

    public func details(forPlaceID id: String) async throws -> MapPlace {
        guard !apiKey.isEmpty else { throw PlacesError.missingAPIKey }

        let asOf = now()
        if let cached = await cache.detail(forPlaceID: id, asOf: asOf) { return cached }

        // Place ids are opaque provider strings, so they are percent-encoded
        // rather than pasted into a path. Hyphen and underscore are left alone
        // because Google's ids are full of them and encoding them would work
        // but make every logged URL unreadable.
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_")
        let encoded = id.addingPercentEncoding(withAllowedCharacters: allowed) ?? id
        guard let url = URL(string: "\(Self.detailsEndpoint.absoluteString)/\(encoded)") else {
            throw PlacesError.malformedResponse
        }

        let response = try await transport.send(HTTPRequest(
            url: url,
            method: "GET",
            headers: [
                "X-Goog-Api-Key": apiKey,
                "X-Goog-FieldMask": Self.detailFieldMask
            ]
        ))
        guard response.isSuccess else {
            throw PlacesError.server(
                status: response.statusCode,
                message: GooglePlacesSource.message(inErrorBody: response.body)
            )
        }

        let place = try Self.place(inDetailBody: response.body, asOf: asOf)
        await cache.storeDetail(place, at: asOf)
        return place
    }

    // MARK: - Photos

    /// Where to get this photograph's bytes, at the size this use needs.
    ///
    /// **A described request, not a fetch** — same seam as everything else in
    /// this package, so the sizing and the URL are testable on Linux and no
    /// `URLSession` comes anywhere near `CardKit`.
    ///
    /// Two things Google's endpoint does that are worth stating, because both
    /// look like bugs from the outside. It answers with a **redirect** to the
    /// real image host rather than the bytes, which `URLSession` follows on
    /// its own — so the app does nothing special and gets image data. And
    /// `maxWidthPx`/`maxHeightPx` are a *bounding box*: the image comes back
    /// scaled to fit inside them with its own aspect ratio intact, never
    /// cropped or stretched to the numbers given. Cropping is the view's job.
    public func photoRequest(for photo: PlacePhoto, use: PlacePhotoUse) -> HTTPRequest? {
        guard !apiKey.isEmpty, !photo.name.isEmpty else { return nil }
        // The name's own slashes are path separators and stay that way;
        // anything else in it gets encoded.
        guard let path = photo.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              var components = URLComponents(
                string: "\(Self.photoEndpoint.absoluteString)/\(path)/media"
              )
        else { return nil }

        components.queryItems = [
            URLQueryItem(name: "maxWidthPx", value: String(photo.pixelWidth(for: use))),
            URLQueryItem(name: "maxHeightPx", value: String(photo.pixelHeight(for: use)))
        ]
        guard let url = components.url else { return nil }

        // The key goes in the header rather than the query string, so it stays
        // out of logs and out of any URL that might get shared.
        return HTTPRequest(url: url, method: "GET", headers: ["X-Goog-Api-Key": apiKey])
    }

    // MARK: - Sending

    private func send<Payload: Encodable>(
        _ payload: Payload,
        to url: URL,
        fieldMask: String
    ) async throws -> [MapPlace] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let body = try? encoder.encode(payload) else { throw PlacesError.malformedResponse }

        let response = try await transport.send(HTTPRequest(
            url: url,
            method: "POST",
            headers: [
                "Content-Type": "application/json",
                "X-Goog-Api-Key": apiKey,
                // Places API (New) bills by the fields asked for and refuses
                // the request outright without this header.
                "X-Goog-FieldMask": fieldMask
            ],
            body: body
        ))
        guard response.isSuccess else {
            throw PlacesError.server(
                status: response.statusCode,
                message: GooglePlacesSource.message(inErrorBody: response.body)
            )
        }
        return try Self.places(inBody: response.body)
    }

    private func clamped(_ radiusMeters: Double) -> Double {
        min(max(radiusMeters, 1), Self.maximumRadiusMeters)
    }

    // MARK: - The request bodies

    private struct Center: Encodable {
        var latitude: Double
        var longitude: Double
    }

    private struct Circle: Encodable {
        var center: Center
        var radius: Double
    }

    private struct Area: Encodable {
        var circle: Circle
    }

    private struct SearchNearby: Encodable {
        var includedTypes: [String]
        var maxResultCount: Int
        var rankPreference: String
        var locationRestriction: Area
    }

    private struct SearchText: Encodable {
        var textQuery: String
        var maxResultCount: Int
        var locationBias: Area
    }

    // MARK: - The responses

    struct RawPlace: Decodable {
        struct Text: Decodable {
            var text: String
        }
        struct Location: Decodable {
            var latitude: Double
            var longitude: Double
        }
        struct OpeningHours: Decodable {
            var openNow: Bool?
            var weekdayDescriptions: [String]?
        }
        struct Photo: Decodable {
            struct Attribution: Decodable {
                var displayName: String?
            }
            var name: String
            var widthPx: Int?
            var heightPx: Int?
            var authorAttributions: [Attribution]?
        }

        var id: String
        var displayName: Text?
        var primaryTypeDisplayName: Text?
        var types: [String]?
        var location: Location?
        var formattedAddress: String?
        var rating: Double?
        var userRatingCount: Int?
        var nationalPhoneNumber: String?
        var websiteUri: String?
        var regularOpeningHours: OpeningHours?
        var photos: [Photo]?
    }

    private struct SearchResult: Decodable {
        var places: [RawPlace]?
    }

    /// A place with no name or no coordinates is dropped; a place with types
    /// we do not recognise is **kept**, as `MapCategory.other`. That is the
    /// difference between this and the geofence parser, which drops it: a pin
    /// saying "nothing in your wallet earns extra here" is a true answer, and
    /// a geofence that can never produce a recommendation is dead weight.
    static func places(inBody body: Data) throws -> [MapPlace] {
        guard let result = try? JSONDecoder().decode(SearchResult.self, from: body) else {
            throw PlacesError.malformedResponse
        }
        var seen: Set<String> = []
        return (result.places ?? []).compactMap { raw in
            guard seen.insert(raw.id).inserted else { return nil }
            return place(from: raw)
        }
    }

    static func place(inDetailBody body: Data, asOf date: Date = Date()) throws -> MapPlace {
        guard let raw = try? JSONDecoder().decode(RawPlace.self, from: body),
              let place = place(from: raw, asOf: date)
        else { throw PlacesError.malformedResponse }
        return place
    }

    static func place(from raw: RawPlace, asOf date: Date = Date()) -> MapPlace? {
        guard let name = raw.displayName?.text, !name.isEmpty,
              let location = raw.location
        else { return nil }

        return MapPlace(
            id: raw.id,
            name: name,
            coordinate: GeoCoordinate(
                latitude: location.latitude,
                longitude: location.longitude
            ),
            placeTypes: raw.types ?? [],
            typeDescription: raw.primaryTypeDisplayName?.text,
            photo: firstPhoto(in: raw.photos),
            rating: raw.rating,
            ratingCount: raw.userRatingCount,
            address: raw.formattedAddress,
            isOpenNow: raw.regularOpeningHours?.openNow,
            hoursToday: todaysHours(in: raw.regularOpeningHours?.weekdayDescriptions, asOf: date),
            phone: raw.nationalPhoneNumber,
            website: raw.websiteUri
        )
    }

    /// The first usable photo, and only the first.
    ///
    /// Google returns up to ten per place and the app draws one. Keeping the
    /// other nine would mean carrying nine handles through every cache and
    /// every model for a gallery that does not exist — and the first is the
    /// one Google ranks highest, which is the one a gallery would open on.
    ///
    /// A photo with an empty `name` is dropped rather than carried: it is a
    /// handle that cannot be fetched, and a nil photo draws the fallback
    /// while a broken one would draw a spinner that never stops.
    static func firstPhoto(in photos: [RawPlace.Photo]?) -> PlacePhoto? {
        guard let raw = photos?.first(where: { !$0.name.isEmpty }) else { return nil }
        return PlacePhoto(
            name: raw.name,
            widthPx: raw.widthPx,
            heightPx: raw.heightPx,
            attributions: (raw.authorAttributions ?? [])
                .compactMap(\.displayName)
                .filter { !$0.isEmpty }
        )
    }

    /// Today's line out of Google's seven.
    ///
    /// `weekdayDescriptions` is already written for a human and already
    /// localised — "Monday: 11:00 AM – 10:00 PM" — and it handles the cases
    /// that assembling a string from open/close times gets wrong: split
    /// shifts, closed days, and places open past midnight. So this picks the
    /// right line and trims the day off the front rather than parsing it.
    ///
    /// Google's array starts on **Monday**; `Calendar`'s weekday starts on
    /// Sunday at 1. Hence the shift.
    static func todaysHours(in descriptions: [String]?, asOf date: Date) -> String? {
        guard let descriptions, descriptions.count == 7 else { return nil }
        let weekday = Calendar(identifier: .gregorian).component(.weekday, from: date)
        let index = (weekday + 5) % 7
        let line = descriptions[index]
        guard let separator = line.range(of: ": ") else { return line }
        let hours = String(line[separator.upperBound...])
        return hours.isEmpty ? line : hours
    }
}
