import XCTest
@testable import CardKit

/// The cache is what keeps a billable API call off the path of somebody just
/// walking to work, so its rules are worth pinning down.
final class MerchantCacheTests: XCTestCase {

    /// One grid square of latitude, in degrees, at the default 250m.
    private let step = 250.0 / 111_194.93

    private var bistro: Merchant {
        Fixture.merchant("bistro", category: .dining, metersNorth: 10)
    }

    // MARK: - The grid

    func testTwoFixesInTheSameSquareShareAnAnswer() {
        let cache = MerchantCache()
        let centre = GeoCoordinate(latitude: 100 * step, longitude: 0)
        let nudged = GeoCoordinate(latitude: 100 * step + step * 0.3, longitude: 0)
        XCTAssertEqual(
            cache.key(for: centre, categories: [.dining]),
            cache.key(for: nudged, categories: [.dining])
        )
    }

    /// The boundary is real and nobody is pretending otherwise: two fixes a few
    /// metres apart can land either side of it. The cost is one extra lookup.
    func testTheNextSquareIsADifferentAnswer() {
        let cache = MerchantCache()
        let centre = GeoCoordinate(latitude: 100 * step, longitude: 0)
        let over = GeoCoordinate(latitude: 100 * step + step * 0.8, longitude: 0)
        XCTAssertNotEqual(
            cache.key(for: centre, categories: [.dining]),
            cache.key(for: over, categories: [.dining])
        )
    }

    /// Degrees of longitude narrow towards the poles. A grid that ignored that
    /// would be a 250m square in Miami and a 125m sliver in Stockholm.
    func testTheGridStaysSquareInMetresAtHighLatitude() {
        let cache = MerchantCache()
        let longitudeStep = step / cos(60 * Double.pi / 180)
        let centre = GeoCoordinate(latitude: 60, longitude: 100 * longitudeStep)

        let eighty = GeoCoordinate(latitude: 60, longitude: centre.longitude + longitudeStep * 0.3)
        let threeHundred = GeoCoordinate(latitude: 60, longitude: centre.longitude + longitudeStep * 1.2)

        XCTAssertEqual(centre.distance(to: eighty), 75, accuracy: 5)
        XCTAssertEqual(
            cache.key(for: centre, categories: [.dining]),
            cache.key(for: eighty, categories: [.dining])
        )
        XCTAssertNotEqual(
            cache.key(for: centre, categories: [.dining]),
            cache.key(for: threeHundred, categories: [.dining])
        )
    }

    /// Asking a different question deserves a different answer. A wallet that
    /// gained a petrol card is asking one, and the stored reply has no petrol
    /// stations in it.
    func testTheCategoriesArePartOfTheKey() {
        let cache = MerchantCache()
        XCTAssertNotEqual(
            cache.key(for: Fixture.anchor, categories: [.dining]),
            cache.key(for: Fixture.anchor, categories: [.dining, .gas])
        )
        XCTAssertEqual(
            cache.key(for: Fixture.anchor, categories: [.gas, .dining]),
            cache.key(for: Fixture.anchor, categories: [.dining, .gas])
        )
    }

    // MARK: - Keeping and forgetting

    func testAStoredAnswerComesBack() {
        var cache = MerchantCache()
        cache.store([bistro], near: Fixture.anchor, categories: [.dining], at: Fixture.inQ3)
        let found = cache.merchants(near: Fixture.anchor, categories: [.dining], asOf: Fixture.inQ3)
        XCTAssertEqual(found?.map(\.id), ["bistro"])
    }

    func testAnUnaskedQuestionHasNoAnswer() {
        var cache = MerchantCache()
        XCTAssertNil(cache.merchants(near: Fixture.anchor, categories: [.dining], asOf: Fixture.inQ3))
    }

    func testAnAnswerGoesStaleAfterItsTime() {
        var cache = MerchantCache(timeToLive: 60)
        cache.store([bistro], near: Fixture.anchor, categories: [.dining], at: Fixture.inQ3)

        XCTAssertNotNil(cache.merchants(
            near: Fixture.anchor,
            categories: [.dining],
            asOf: Fixture.inQ3.addingTimeInterval(30)
        ))
        XCTAssertNil(cache.merchants(
            near: Fixture.anchor,
            categories: [.dining],
            asOf: Fixture.inQ3.addingTimeInterval(90)
        ))
    }

    /// A year of commuting must not fill the disk, and the square somebody
    /// visits every day must not be the one that gets dropped.
    func testTheLeastRecentlyUsedSquareIsTheOneDropped() {
        var cache = MerchantCache(maximumEntries: 2)
        let home = GeoCoordinate(latitude: 0, longitude: 0.5)
        let work = GeoCoordinate(latitude: 10, longitude: 0.5)
        let holiday = GeoCoordinate(latitude: 20, longitude: 0.5)

        cache.store([bistro], near: home, categories: [.dining], at: Fixture.inQ3)
        cache.store([bistro], near: work, categories: [.dining], at: Fixture.inQ3)
        // Home is used again, so work becomes the oldest.
        _ = cache.merchants(near: home, categories: [.dining], asOf: Fixture.inQ3)
        cache.store([bistro], near: holiday, categories: [.dining], at: Fixture.inQ3)

        XCTAssertEqual(cache.count, 2)
        XCTAssertNotNil(cache.merchants(near: home, categories: [.dining], asOf: Fixture.inQ3))
        XCTAssertNotNil(cache.merchants(near: holiday, categories: [.dining], asOf: Fixture.inQ3))
        XCTAssertNil(cache.merchants(near: work, categories: [.dining], asOf: Fixture.inQ3))
    }

    // MARK: - Surviving a relaunch

    /// The app is killed constantly. A cache that only lived in memory would be
    /// empty every time it mattered.
    func testTheCacheOutlivesTheProcess() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("places-cache-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = MerchantCacheStore(fileURL: url)
        await store.store([bistro], near: Fixture.anchor, categories: [.dining], at: Fixture.inQ3)

        let reopened = MerchantCacheStore(fileURL: url)
        let found = await reopened.merchants(
            near: Fixture.anchor,
            categories: [.dining],
            asOf: Fixture.inQ3
        )
        XCTAssertEqual(found?.map(\.id), ["bistro"])
    }
}
