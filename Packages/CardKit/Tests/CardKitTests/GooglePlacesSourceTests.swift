import XCTest
@testable import CardKit

/// Everything about the Places integration except the one line that opens a
/// socket. The canned bodies below are the shape Places API (New) actually
/// returns for `places:searchNearby` with our field mask.
final class GooglePlacesSourceTests: XCTestCase {

    /// Replies in order, and remembers what it was asked.
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

        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            lock.lock(); defer { lock.unlock() }
            sent.append(request)
            return replies.isEmpty ? HTTPResponse(statusCode: 200, body: Data("{}".utf8)) : replies.removeFirst()
        }
    }

    private let restaurantAndBarber = """
    {"places":[
      {"id":"p1",
       "displayName":{"text":"Corner Bistro","languageCode":"en"},
       "types":["restaurant","food","point_of_interest","establishment"],
       "location":{"latitude":40.7581,"longitude":-73.9856}},
      {"id":"p2",
       "displayName":{"text":"Hudson Barbers","languageCode":"en"},
       "types":["hair_care","point_of_interest","establishment"],
       "location":{"latitude":40.7582,"longitude":-73.9857}}
    ]}
    """

    private let mall = """
    {"places":[
      {"id":"m1",
       "displayName":{"text":"Riverside Centre","languageCode":"en"},
       "types":["shopping_mall","point_of_interest","establishment"],
       "location":{"latitude":40.7581,"longitude":-73.9856}}
    ]}
    """

    private func source(
        _ transport: FakeTransport,
        key: String = "test-key",
        cache: MerchantCacheStore = MerchantCacheStore(),
        now: @escaping @Sendable () -> Date = { Fixture.inQ3 }
    ) -> GooglePlacesSource {
        GooglePlacesSource(apiKey: key, transport: transport, cache: cache, now: now)
    }

    private func lookUp(
        _ source: GooglePlacesSource,
        categories: Set<SpendingCategory> = [.dining],
        at coordinate: GeoCoordinate = Fixture.anchor,
        radius: Double = 2_000
    ) async throws -> [Merchant] {
        try await source.merchants(near: coordinate, radiusMeters: radius, categories: categories)
    }

    // MARK: - Reading the answer

    func testAPlaceBecomesAMerchantWithACategory() async throws {
        let found = try await lookUp(source(FakeTransport(json: restaurantAndBarber)))
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].id, "p1")
        XCTAssertEqual(found[0].name, "Corner Bistro")
        XCTAssertEqual(found[0].category, .dining)
        XCTAssertEqual(found[0].confidence, .exact)
        XCTAssertEqual(found[0].coordinate.latitude, 40.7581, accuracy: 0.00001)
    }

    /// Google returns whatever is nearby, including places no card has a
    /// category for. Those are dropped rather than guessed at.
    func testPlacesWithNoCategoryWeRecogniseAreDropped() async throws {
        let found = try await lookUp(source(FakeTransport(json: restaurantAndBarber)))
        XCTAssertFalse(found.contains { $0.id == "p2" })
    }

    /// `point_of_interest` and `establishment` are on nearly every place Google
    /// returns. If they counted as ambiguous, no business would ever be named.
    func testTheTypesGooglePutsOnEverythingDoNotDowngradeConfidence() async throws {
        let found = try await lookUp(source(FakeTransport(json: restaurantAndBarber)))
        XCTAssertEqual(found.first?.confidence, .exact)
    }

    func testAMallIsResolvedToACategoryAndNotToAShop() async throws {
        let found = try await lookUp(
            source(FakeTransport(json: mall)),
            categories: [.departmentStore]
        )
        XCTAssertEqual(found.first?.confidence, .categoryOnly)
        XCTAssertEqual(found.first?.category, .departmentStore)
    }

    func testAPlaceMissingItsNameOrCoordinatesIsSkipped() async throws {
        let partial = """
        {"places":[
          {"id":"a","types":["restaurant"],"location":{"latitude":1,"longitude":1}},
          {"id":"b","displayName":{"text":"No Location"},"types":["restaurant"]},
          {"id":"c","displayName":{"text":"Fine"},"types":["restaurant"],"location":{"latitude":40.75,"longitude":-73.98}}
        ]}
        """
        let found = try await lookUp(source(FakeTransport(json: partial)))
        XCTAssertEqual(found.map(\.id), ["c"])
    }

    func testAnEmptyAnswerIsNotAnError() async throws {
        let found = try await lookUp(source(FakeTransport(json: #"{"places":[]}"#)))
        XCTAssertTrue(found.isEmpty)
    }

    func testRubbishInTheBodyThrows() async {
        do {
            _ = try await lookUp(source(FakeTransport(json: "not json at all")))
            XCTFail("expected a decoding failure")
        } catch {
            XCTAssertEqual(error as? PlacesError, .malformedResponse)
        }
    }

    // MARK: - Asking the question

    func testTheRequestCarriesTheKeyAndTheFieldMask() async throws {
        let transport = FakeTransport(json: restaurantAndBarber)
        _ = try await lookUp(source(transport, key: "abc123"))

        let request = try XCTUnwrap(transport.sent.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url, GooglePlacesSource.endpoint)
        XCTAssertEqual(request.headers["X-Goog-Api-Key"], "abc123")
        // Places API (New) refuses the call outright without this header.
        XCTAssertEqual(
            request.headers["X-Goog-FieldMask"],
            "places.id,places.displayName,places.types,places.location"
        )
    }

    /// Only the types the wallet could earn a bonus on. Twenty results is the
    /// ceiling, so spending them on categories no card pays extra for would
    /// leave nothing to watch.
    func testTheRequestOnlyAsksForTypesTheWalletCaresAbout() async throws {
        let transport = FakeTransport(json: restaurantAndBarber)
        _ = try await lookUp(source(transport), categories: [.dining])

        let body = try XCTUnwrap(transport.sent.first?.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let types = try XCTUnwrap(json["includedTypes"] as? [String])

        XCTAssertTrue(types.contains("restaurant"))
        XCTAssertTrue(types.contains("cafe"))
        XCTAssertFalse(types.contains("gas_station"))
        XCTAssertLessThanOrEqual(types.count, GooglePlacesSource.maximumIncludedTypes)
        XCTAssertEqual(json["maxResultCount"] as? Int, 20)
        // Google's default is prominence, which would hand back the famous
        // restaurant a mile away over the one next door.
        XCTAssertEqual(json["rankPreference"] as? String, "DISTANCE")
    }

    func testTheRadiusIsClampedToGooglesCeiling() async throws {
        let transport = FakeTransport(json: restaurantAndBarber)
        _ = try await lookUp(source(transport), radius: 999_999)

        let body = try XCTUnwrap(transport.sent.first?.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let restriction = try XCTUnwrap(json["locationRestriction"] as? [String: Any])
        let circle = try XCTUnwrap(restriction["circle"] as? [String: Any])
        XCTAssertEqual(circle["radius"] as? Double, GooglePlacesSource.maximumRadiusMeters)
    }

    /// A wallet of flat-rate cards has no category worth a geofence, so there
    /// is nothing to ask and no call to bill.
    func testNoRelevantCategoriesMeansNoRequestAtAll() async throws {
        let transport = FakeTransport(json: restaurantAndBarber)
        let found = try await lookUp(source(transport), categories: [])
        XCTAssertTrue(found.isEmpty)
        XCTAssertEqual(transport.callCount, 0)
    }

    // MARK: - Failing

    func testNoKeyIsAnErrorRatherThanAnEmptyAnswer() async {
        let transport = FakeTransport(json: restaurantAndBarber)
        do {
            _ = try await lookUp(source(transport, key: ""))
            XCTFail("expected a missing-key failure")
        } catch {
            XCTAssertEqual(error as? PlacesError, .missingAPIKey)
        }
        XCTAssertEqual(transport.callCount, 0)
    }

    /// Whatever Google says went wrong is what ends up in the app's own event
    /// log, because "something failed" is not a thing anyone can act on.
    func testARefusalCarriesGooglesOwnWording() async {
        let refusal = """
        {"error":{"code":403,"message":"The provided API key is expired.","status":"PERMISSION_DENIED"}}
        """
        let transport = FakeTransport(json: refusal, status: 403)
        do {
            _ = try await lookUp(source(transport))
            XCTFail("expected a server failure")
        } catch {
            XCTAssertEqual(
                error as? PlacesError,
                .server(status: 403, message: "The provided API key is expired.")
            )
        }
    }

    func testARefusalWithNoBodyStillSaysSomething() async {
        let transport = FakeTransport(json: "", status: 500)
        do {
            _ = try await lookUp(source(transport))
            XCTFail("expected a server failure")
        } catch {
            guard case .server(let status, let message)? = error as? PlacesError else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertEqual(status, 500)
            XCTAssertFalse(message.isEmpty)
        }
    }

    // MARK: - Asking as rarely as possible

    func testTheSameSpotIsOnlyLookedUpOnce() async throws {
        let transport = FakeTransport(json: restaurantAndBarber)
        let places = source(transport, cache: MerchantCacheStore())

        let first = try await lookUp(places)
        let second = try await lookUp(places)

        XCTAssertEqual(transport.callCount, 1)
        XCTAssertEqual(first.map(\.id), second.map(\.id))
    }

    func testSomewhereElseIsLookedUpAgain() async throws {
        let transport = FakeTransport([
            HTTPResponse(statusCode: 200, body: Data(restaurantAndBarber.utf8)),
            HTTPResponse(statusCode: 200, body: Data(restaurantAndBarber.utf8))
        ])
        let places = source(transport, cache: MerchantCacheStore())

        _ = try await lookUp(places)
        _ = try await lookUp(places, at: Fixture.offset(Fixture.anchor, metersNorth: 6_000))

        XCTAssertEqual(transport.callCount, 2)
    }

    /// A wallet that gained a petrol card is asking a different question, and
    /// the old answer does not contain petrol stations.
    func testADifferentWalletAsksAgain() async throws {
        let transport = FakeTransport([
            HTTPResponse(statusCode: 200, body: Data(restaurantAndBarber.utf8)),
            HTTPResponse(statusCode: 200, body: Data(restaurantAndBarber.utf8))
        ])
        let places = source(transport, cache: MerchantCacheStore())

        _ = try await lookUp(places, categories: [.dining])
        _ = try await lookUp(places, categories: [.dining, .gas])

        XCTAssertEqual(transport.callCount, 2)
    }

    func testAStaleAnswerIsFetchedAgain() async throws {
        let transport = FakeTransport([
            HTTPResponse(statusCode: 200, body: Data(restaurantAndBarber.utf8)),
            HTTPResponse(statusCode: 200, body: Data(restaurantAndBarber.utf8))
        ])
        let cache = MerchantCacheStore()
        let clock = MovableClock(Fixture.inQ3)

        let places = GooglePlacesSource(
            apiKey: "test-key",
            transport: transport,
            cache: cache,
            now: { clock.now }
        )

        _ = try await lookUp(places)
        clock.advance(days: 3)
        _ = try await lookUp(places)
        XCTAssertEqual(transport.callCount, 1, "three days is still fresh")

        clock.advance(days: 8)
        _ = try await lookUp(places)
        XCTAssertEqual(transport.callCount, 2)
    }

    private final class MovableClock: @unchecked Sendable {
        private let lock = NSLock()
        private var date: Date

        init(_ date: Date) { self.date = date }

        var now: Date {
            lock.lock(); defer { lock.unlock() }
            return date
        }

        func advance(days: Int) {
            lock.lock(); defer { lock.unlock() }
            date = date.addingTimeInterval(Double(days) * 24 * 60 * 60)
        }
    }
}
