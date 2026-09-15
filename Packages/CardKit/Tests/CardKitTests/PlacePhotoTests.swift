import XCTest
@testable import CardKit

/// The photograph half of the Places integration: what comes back from a
/// search, how big an image the app asks for, and what it credits.
///
/// Worth the same note the other Places tests carry — **green here says
/// nothing about whether Google accepts the request.** What it does cover is
/// every line between the response arriving and a view drawing it, which is
/// where the mistakes that are hard to see on a phone actually live.
final class PlacePhotoTests: XCTestCase {

    private final class FakeTransport: HTTPTransport, @unchecked Sendable {
        private let lock = NSLock()
        private let body: Data
        private(set) var sent: [HTTPRequest] = []

        init(json: String) { self.body = Data(json.utf8) }

        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            lock.lock(); defer { lock.unlock() }
            sent.append(request)
            return HTTPResponse(statusCode: 200, body: body)
        }
    }

    private let anchor = GeoCoordinate(latitude: 33.7838, longitude: -84.3810)

    /// The shape Places API (New) returns for `places.photos`.
    private let withPhoto = """
    {"places":[
      {"id":"p1",
       "displayName":{"text":"Peachtree Chophouse"},
       "types":["restaurant","food"],
       "location":{"latitude":33.7840,"longitude":-84.3820},
       "primaryTypeDisplayName":{"text":"Steakhouse"},
       "rating":4.6,
       "userRatingCount":1730,
       "photos":[
         {"name":"places/p1/photos/AeJbb3first","widthPx":4032,"heightPx":3024,
          "authorAttributions":[{"displayName":"Alexa H."}]},
         {"name":"places/p1/photos/AeJbb3second","widthPx":1200,"heightPx":900}
       ]}
    ]}
    """

    // MARK: - Parsing

    func testSearchCarriesTheFirstPhoto() async throws {
        let transport = FakeTransport(json: withPhoto)
        let source = GooglePlaceSearchSource(apiKey: "k", transport: transport)

        let places = try await source.places(
            near: anchor,
            radiusMeters: 3_000,
            categories: [.restaurants]
        )

        let photo = try XCTUnwrap(places.first?.photo)
        XCTAssertEqual(photo.name, "places/p1/photos/AeJbb3first")
        XCTAssertEqual(photo.widthPx, 4032)
        XCTAssertEqual(photo.attributions, ["Alexa H."])
    }

    func testTheSearchAsksForPhotos() async throws {
        let transport = FakeTransport(json: withPhoto)
        let source = GooglePlaceSearchSource(apiKey: "k", transport: transport)
        _ = try await source.places(near: anchor, radiusMeters: 3_000, categories: [.restaurants])

        let mask = try XCTUnwrap(transport.sent.first?.headers["X-Goog-FieldMask"])
        XCTAssertTrue(mask.contains("places.photos"), "the field mask has to ask, or there are no photos to draw")
    }

    /// A place with no photos is the ordinary case, not an error — most of a
    /// suburban high street has none.
    func testAPlaceWithoutPhotosParsesFine() {
        XCTAssertNil(GooglePlaceSearchSource.firstPhoto(in: nil))
        XCTAssertNil(GooglePlaceSearchSource.firstPhoto(in: []))
    }

    /// A handle with no name cannot be fetched, so it must not be carried: the
    /// view would draw a spinner waiting for an image that can never arrive,
    /// where a nil draws the fallback immediately.
    func testAPhotoWithNoNameIsSkipped() {
        let photos: [GooglePlaceSearchSource.RawPlace.Photo] = [
            .init(name: "", widthPx: nil, heightPx: nil, authorAttributions: nil),
            .init(name: "places/x/photos/real", widthPx: nil, heightPx: nil, authorAttributions: nil)
        ]
        XCTAssertEqual(GooglePlaceSearchSource.firstPhoto(in: photos)?.name, "places/x/photos/real")
    }

    // MARK: - Sizing

    func testAskingForFewerPixelsThanTheImageHas() {
        let big = PlacePhoto(name: "n", widthPx: 4032, heightPx: 3024)
        XCTAssertEqual(big.pixelWidth(for: .row), PlacePhotoUse.row.pixelWidth)
        XCTAssertEqual(big.pixelWidth(for: .hero), PlacePhotoUse.hero.pixelWidth)
    }

    /// Asking for 1170 pixels of a 640-pixel photo buys an upscale at full
    /// price, and it looks worse than the honest size.
    func testNeverAsksForMorePixelsThanExist() {
        let small = PlacePhoto(name: "n", widthPx: 640, heightPx: 480)
        XCTAssertEqual(small.pixelWidth(for: .hero), 640)
        XCTAssertEqual(small.pixelHeight(for: .hero), 480)
    }

    func testAPhotoThatNeverStatedItsSizeAsksForTheFullAmount() {
        let unknown = PlacePhoto(name: "n")
        XCTAssertEqual(unknown.pixelWidth(for: .card), PlacePhotoUse.card.pixelWidth)
    }

    /// The row bucket has to be genuinely small, or an 88-point thumbnail is
    /// paid for at hero resolution twenty times per screen.
    func testTheRowBucketIsSmallerThanTheHero() {
        XCTAssertLessThan(PlacePhotoUse.row.pixelWidth, PlacePhotoUse.hero.pixelWidth)
    }

    // MARK: - Caching

    func testTheSamePhotoAtTwoSizesIsTwoCacheEntries() {
        let photo = PlacePhoto(name: "places/p1/photos/abc")
        XCTAssertNotEqual(photo.cacheKey(for: .row), photo.cacheKey(for: .hero))
    }

    func testTheCacheKeyIsStableAcrossValues() {
        let one = PlacePhoto(name: "places/p1/photos/abc", widthPx: 100)
        let two = PlacePhoto(name: "places/p1/photos/abc", widthPx: 4000)
        XCTAssertEqual(one.cacheKey(for: .row), two.cacheKey(for: .row),
                       "the same image at the same size is one download, whatever else the model knows about it")
    }

    /// It becomes a filename, so it cannot contain a path separator.
    func testTheCacheKeyIsSafeAsAFilename() {
        let key = PlacePhoto(name: "places/p1/photos/a+b/c").cacheKey(for: .card)
        XCTAssertFalse(key.contains("/"))
        XCTAssertFalse(key.isEmpty)
    }

    func testDifferentPhotosGetDifferentKeys() {
        let one = PlacePhoto(name: "places/p1/photos/abc").cacheKey(for: .row)
        let two = PlacePhoto(name: "places/p1/photos/abd").cacheKey(for: .row)
        XCTAssertNotEqual(one, two)
    }

    // MARK: - The request

    func testThePhotoRequestPutsTheKeyInTheHeaderAndTheSizeInTheQuery() throws {
        let source = GooglePlaceSearchSource(apiKey: "secret", transport: FakeTransport(json: "{}"))
        let request = try XCTUnwrap(
            source.photoRequest(for: PlacePhoto(name: "places/p1/photos/abc"), use: .hero)
        )

        XCTAssertEqual(request.headers["X-Goog-Api-Key"], "secret")
        let url = request.url.absoluteString
        XCTAssertTrue(url.contains("places/p1/photos/abc/media"), url)
        XCTAssertTrue(url.contains("maxWidthPx=1170"), url)
        XCTAssertFalse(url.contains("secret"), "a key in the URL ends up in logs and in anything shared")
    }

    func testNoKeyMeansNoRequest() {
        let source = GooglePlaceSearchSource(apiKey: "", transport: FakeTransport(json: "{}"))
        XCTAssertNil(source.photoRequest(for: PlacePhoto(name: "places/p1/photos/abc"), use: .row))
    }

    /// The two sources that have no images say so rather than building a URL
    /// that would 404.
    func testSourcesWithoutPhotosReturnNothing() {
        XCTAssertNil(EmptyPlaceSearchSource().photoRequest(for: PlacePhoto(name: "n"), use: .row))
        XCTAssertNil(StaticPlaceSearchSource([]).photoRequest(for: PlacePhoto(name: "n"), use: .row))
    }

    // MARK: - Credit

    func testTheCreditReadsAsASentence() {
        XCTAssertEqual(
            PlacePhoto(name: "n", attributions: ["Alexa H."]).attributionText,
            "Photo by Alexa H."
        )
        XCTAssertEqual(
            PlacePhoto(name: "n", attributions: ["Alexa H.", "Sam T.", "Kim P."]).attributionText,
            "Photo by Alexa H. and 2 more"
        )
    }

    func testNobodyCreditedIsNoCreditLine() {
        XCTAssertNil(PlacePhoto(name: "n").attributionText)
    }

    /// An attribution that came back as an empty string is nobody, and would
    /// otherwise render as a bare "Photo by" under the image.
    func testAnEmptyCreditIsDropped() {
        let photos: [GooglePlaceSearchSource.RawPlace.Photo] = [
            .init(
                name: "places/x/photos/y",
                widthPx: nil,
                heightPx: nil,
                authorAttributions: [.init(displayName: ""), .init(displayName: nil)]
            )
        ]
        XCTAssertEqual(GooglePlaceSearchSource.firstPhoto(in: photos)?.attributions, [])
    }

    // MARK: - Merging

    /// Opening a place runs a details lookup, and details can come back
    /// without a photo. The row already had one on screen; taking it away on
    /// tap is a flash of emptiness in the worst possible place.
    func testDetailsWithoutAPhotoKeepTheOneTheRowHad() {
        let listed = MapPlace(
            id: "p1",
            name: "Peachtree Chophouse",
            coordinate: anchor,
            photo: PlacePhoto(name: "places/p1/photos/abc")
        )
        let detail = MapPlace(id: "p1", name: "Peachtree Chophouse", coordinate: anchor, phone: "+1 404 555 0100")

        let merged = listed.merging(detail)
        XCTAssertEqual(merged.photo?.name, "places/p1/photos/abc")
        XCTAssertEqual(merged.phone, "+1 404 555 0100")
    }

    func testDetailsWithABetterPhotoWin() {
        let listed = MapPlace(id: "p1", name: "X", coordinate: anchor, photo: PlacePhoto(name: "old"))
        let detail = MapPlace(id: "p1", name: "X", coordinate: anchor, photo: PlacePhoto(name: "new"))
        XCTAssertEqual(listed.merging(detail).photo?.name, "new")
    }
}
