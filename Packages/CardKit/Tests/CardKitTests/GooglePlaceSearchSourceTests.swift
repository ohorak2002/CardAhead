import XCTest
@testable import CardKit

/// The map's three Places calls, everywhere except the line that opens a
/// socket. The canned bodies are the shape Places API (New) actually returns
/// for the field masks in `GooglePlaceSearchSource`.
final class GooglePlaceSearchSourceTests: XCTestCase {

    private final class FakeTransport: HTTPTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var replies: [HTTPResponse]
        private(set) var sent: [HTTPRequest] = []

        init(_ replies: [HTTPResponse]) {
            self.replies = replies
        }

        convenience init(json: String, status: Int = 200) {
            self.init([HTTPResponse(statusCode: status, body: Data(json.utf8))])
        }

        var callCount: Int {
            lock.lock(); defer { lock.unlock() }
            return sent.count
        }

        var lastRequest: HTTPRequest? {
            lock.lock(); defer { lock.unlock() }
            return sent.last
        }

        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            lock.lock(); defer { lock.unlock() }
            sent.append(request)
            return replies.isEmpty
                ? HTTPResponse(statusCode: 200, body: Data("{}".utf8))
                : replies.removeFirst()
        }
    }

    private let anchor = GeoCoordinate(latitude: 33.7838, longitude: -84.3810)

    private let mixedBlock = """
    {"places":[
      {"id":"p1",
       "displayName":{"text":"The Capital Grille","languageCode":"en"},
       "primaryTypeDisplayName":{"text":"Steakhouse","languageCode":"en"},
       "types":["steak_house","restaurant","food","point_of_interest"],
       "location":{"latitude":33.7840,"longitude":-84.3815},
       "rating":4.6,"userRatingCount":1234},
      {"id":"p2",
       "displayName":{"text":"Neighbourhood Gym","languageCode":"en"},
       "types":["gym","health","point_of_interest"],
       "location":{"latitude":33.7845,"longitude":-84.3820}},
      {"id":"p3",
       "displayName":{"text":"Lenox Square","languageCode":"en"},
       "types":["shopping_mall","store","point_of_interest"],
       "location":{"latitude":33.8465,"longitude":-84.3620}}
    ]}
    """

    // MARK: - Parsing a search

    func testKeepsPlacesNoCardEarnsAt() async throws {
        let transport = FakeTransport(json: mixedBlock)
        let source = GooglePlaceSearchSource(apiKey: "k", transport: transport)

        let places = try await source.places(near: anchor, radiusMeters: 2_000, categories: [])

        XCTAssertEqual(places.count, 3, "the geofence parser drops the gym; the map must not")
        let gym = places.first { $0.id == "p2" }
        XCTAssertEqual(gym?.mapCategory, .other)
        XCTAssertNil(gym?.spendingCategory)
    }

    func testUsesGooglesOwnWordsForTheTypeWhenItHasThem() async throws {
        let transport = FakeTransport(json: mixedBlock)
        let source = GooglePlaceSearchSource(apiKey: "k", transport: transport)

        let places = try await source.places(near: anchor, radiusMeters: 2_000, categories: [])
        XCTAssertEqual(places.first { $0.id == "p1" }?.typeDescription, "Steakhouse")
        XCTAssertEqual(places.first { $0.id == "p1" }?.rating, 4.6)
        XCTAssertEqual(places.first { $0.id == "p1" }?.ratingCount, 1234)
    }

    func testAPlaceWithNoNameOrNoCoordinatesIsDropped() throws {
        let body = """
        {"places":[
          {"id":"a","types":["restaurant"],"location":{"latitude":1,"longitude":2}},
          {"id":"b","displayName":{"text":"Nameless"},"types":["restaurant"]},
          {"id":"c","displayName":{"text":"Fine"},"types":["restaurant"],"location":{"latitude":1,"longitude":2}}
        ]}
        """
        let places = try GooglePlaceSearchSource.places(inBody: Data(body.utf8))
        XCTAssertEqual(places.map(\.id), ["c"])
    }

    func testTheSamePlaceTwiceComesBackOnce() throws {
        let body = """
        {"places":[
          {"id":"dup","displayName":{"text":"One"},"types":["restaurant"],"location":{"latitude":1,"longitude":2}},
          {"id":"dup","displayName":{"text":"One"},"types":["restaurant"],"location":{"latitude":1,"longitude":2}}
        ]}
        """
        XCTAssertEqual(try GooglePlaceSearchSource.places(inBody: Data(body.utf8)).count, 1)
    }

    func testMalformedBodyThrowsRatherThanReturningNothing() {
        XCTAssertThrowsError(try GooglePlaceSearchSource.places(inBody: Data("not json".utf8)))
    }

    // MARK: - The request

    func testNearbySearchAsksForTheRightThings() async throws {
        let transport = FakeTransport(json: mixedBlock)
        let source = GooglePlaceSearchSource(apiKey: "secret", transport: transport)

        _ = try await source.places(near: anchor, radiusMeters: 2_000, categories: [.restaurants])
        let request = try XCTUnwrap(transport.lastRequest)

        XCTAssertEqual(request.url, GooglePlaceSearchSource.nearbyEndpoint)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.headers["X-Goog-Api-Key"], "secret")
        XCTAssertEqual(request.headers["X-Goog-FieldMask"], GooglePlaceSearchSource.searchFieldMask)

        let body = String(decoding: try XCTUnwrap(request.body), as: UTF8.self)
        XCTAssertTrue(body.contains("\"restaurant\""))
        XCTAssertFalse(body.contains("\"gas_station\""), "asking for types nobody ticked wastes the twenty results")
        XCTAssertTrue(body.contains("DISTANCE"), "prominence would rank the famous place across town first")
    }

    func testTextSearchBiasesRatherThanRestricts() async throws {
        let transport = FakeTransport(json: mixedBlock)
        let source = GooglePlaceSearchSource(apiKey: "k", transport: transport)

        _ = try await source.places(matching: "capital grille", near: anchor, radiusMeters: 2_000)
        let request = try XCTUnwrap(transport.lastRequest)

        XCTAssertEqual(request.url, GooglePlaceSearchSource.textEndpoint)
        let body = String(decoding: try XCTUnwrap(request.body), as: UTF8.self)
        XCTAssertTrue(body.contains("locationBias"))
        XCTAssertFalse(
            body.contains("locationRestriction"),
            "a named shop just outside the radius is still the shop they meant"
        )
    }

    func testAnEmptyQueryNeverReachesTheNetwork() async throws {
        let transport = FakeTransport(json: mixedBlock)
        let source = GooglePlaceSearchSource(apiKey: "k", transport: transport)

        let places = try await source.places(matching: "   ", near: anchor, radiusMeters: 2_000)
        XCTAssertTrue(places.isEmpty)
        XCTAssertEqual(transport.callCount, 0)
    }

    func testMissingKeyIsReportedRatherThanSwallowed() async {
        let source = GooglePlaceSearchSource(apiKey: "", transport: FakeTransport(json: "{}"))
        do {
            _ = try await source.places(near: anchor, radiusMeters: 2_000, categories: [])
            XCTFail("expected a missing-key error")
        } catch {
            XCTAssertEqual(error as? PlacesError, .missingAPIKey)
        }
    }

    func testAServerRefusalCarriesGooglesOwnMessage() async {
        let refusal = """
        {"error":{"code":400,"message":"Invalid included type: nonsense_store","status":"INVALID_ARGUMENT"}}
        """
        let source = GooglePlaceSearchSource(
            apiKey: "k",
            transport: FakeTransport(json: refusal, status: 400)
        )
        do {
            _ = try await source.places(near: anchor, radiusMeters: 2_000, categories: [])
            XCTFail("expected a server error")
        } catch let error as PlacesError {
            guard case .server(let status, let message) = error else {
                return XCTFail("expected .server, got \(error)")
            }
            XCTAssertEqual(status, 400)
            XCTAssertTrue(message.contains("nonsense_store"), "got \(message)")
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    // MARK: - Caching

    func testTheSameQuestionFromTheSameCornerIsAskedOnce() async throws {
        let transport = FakeTransport([
            HTTPResponse(statusCode: 200, body: Data(mixedBlock.utf8)),
            HTTPResponse(statusCode: 200, body: Data(mixedBlock.utf8))
        ])
        let source = GooglePlaceSearchSource(apiKey: "k", transport: transport)

        _ = try await source.places(near: anchor, radiusMeters: 2_000, categories: [.restaurants])
        _ = try await source.places(near: anchor, radiusMeters: 2_000, categories: [.restaurants])
        XCTAssertEqual(transport.callCount, 1)
    }

    func testADifferentRadiusIsADifferentQuestion() async throws {
        let transport = FakeTransport([
            HTTPResponse(statusCode: 200, body: Data(mixedBlock.utf8)),
            HTTPResponse(statusCode: 200, body: Data(mixedBlock.utf8))
        ])
        let source = GooglePlaceSearchSource(apiKey: "k", transport: transport)

        _ = try await source.places(near: anchor, radiusMeters: 800, categories: [.restaurants])
        _ = try await source.places(near: anchor, radiusMeters: 16_000, categories: [.restaurants])
        XCTAssertEqual(transport.callCount, 2)
    }

    // MARK: - Details

    private let detailBody = """
    {"id":"p1",
     "displayName":{"text":"The Capital Grille","languageCode":"en"},
     "primaryTypeDisplayName":{"text":"Steakhouse","languageCode":"en"},
     "types":["steak_house","restaurant"],
     "location":{"latitude":33.7840,"longitude":-84.3815},
     "formattedAddress":"255 E Paces Ferry Rd NE, Atlanta, GA 30305, USA",
     "rating":4.6,"userRatingCount":1234,
     "nationalPhoneNumber":"(404) 262-1162",
     "websiteUri":"https://www.thecapitalgrille.com/",
     "regularOpeningHours":{"openNow":true,"weekdayDescriptions":[
       "Monday: 11:00 AM – 10:00 PM",
       "Tuesday: 11:00 AM – 10:00 PM",
       "Wednesday: 11:00 AM – 10:00 PM",
       "Thursday: 11:00 AM – 10:00 PM",
       "Friday: 11:00 AM – 11:00 PM",
       "Saturday: 4:00 – 11:00 PM",
       "Sunday: Closed"]}}
    """

    func testDetailsFillInEverythingTheListDoesNotPayFor() async throws {
        let transport = FakeTransport(json: detailBody)
        let source = GooglePlaceSearchSource(apiKey: "k", transport: transport)

        let place = try await source.details(forPlaceID: "p1")
        XCTAssertEqual(place.phone, "(404) 262-1162")
        XCTAssertEqual(place.website, "https://www.thecapitalgrille.com/")
        XCTAssertEqual(place.isOpenNow, true)
        XCTAssertEqual(place.address, "255 E Paces Ferry Rd NE, Atlanta, GA 30305, USA")

        let request = try XCTUnwrap(transport.lastRequest)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(
            request.headers["X-Goog-FieldMask"],
            GooglePlaceSearchSource.detailFieldMask
        )
        XCTAssertFalse(
            request.headers["X-Goog-FieldMask"]?.contains("places.") ?? true,
            "a details request returns one place, and a list mask is rejected outright"
        )
    }

    func testDetailsAreAskedForOncePerPlace() async throws {
        let transport = FakeTransport([
            HTTPResponse(statusCode: 200, body: Data(detailBody.utf8)),
            HTTPResponse(statusCode: 200, body: Data(detailBody.utf8))
        ])
        let source = GooglePlaceSearchSource(apiKey: "k", transport: transport)

        _ = try await source.details(forPlaceID: "p1")
        _ = try await source.details(forPlaceID: "p1")
        XCTAssertEqual(transport.callCount, 1, "the expensive call, paid for twice, is the one to watch")
    }

    // MARK: - Opening hours

    func testTodaysHoursComeFromGooglesOwnLineForToday() {
        let descriptions = [
            "Monday: 11:00 AM – 10:00 PM",
            "Tuesday: closed for refurbishment",
            "Wednesday: 11:00 AM – 10:00 PM",
            "Thursday: 11:00 AM – 10:00 PM",
            "Friday: 11:00 AM – 11:00 PM",
            "Saturday: 4:00 – 11:00 PM",
            "Sunday: Closed"
        ]
        // Google's array starts on Monday; Calendar's weekday starts on Sunday.
        // 2026-09-13 is a Sunday, so the last line is the right one.
        let sunday = Fixture.makeDate(2026, 9, 13)
        XCTAssertEqual(
            GooglePlaceSearchSource.todaysHours(in: descriptions, asOf: sunday),
            "Closed"
        )

        let monday = Fixture.makeDate(2026, 9, 14)
        XCTAssertEqual(
            GooglePlaceSearchSource.todaysHours(in: descriptions, asOf: monday),
            "11:00 AM – 10:00 PM"
        )
    }

    func testAShortWeekIsIgnoredRatherThanIndexedInto() {
        XCTAssertNil(GooglePlaceSearchSource.todaysHours(in: ["Monday: 9-5"], asOf: Date()))
        XCTAssertNil(GooglePlaceSearchSource.todaysHours(in: nil, asOf: Date()))
    }

    // MARK: - The empty source

    func testNoKeyMeansNoPinsAndNoInventedOnes() async throws {
        let source = EmptyPlaceSearchSource()
        let places = try await source.places(
            near: anchor,
            radiusMeters: 5_000,
            categories: []
        )
        XCTAssertTrue(places.isEmpty)
        XCTAssertTrue(source.sourceDescription.contains("no place provider"))
    }
}
