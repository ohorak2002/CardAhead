import Foundation
import os
import CardKit

/// Puts `CardKit`'s described requests on the wire.
///
/// The whole of the Places integration — the URL, the field mask, the parsing,
/// the cache — lives in `CardKit` and is tested on Linux. This is the twenty
/// lines that could not be.
struct URLSessionTransport: HTTPTransport {

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        // A geofence redraw that has not answered in fifteen seconds has missed
        // its moment. The user has walked on, and the next significant location
        // change will ask again from wherever they are by then.
        configuration.timeoutIntervalForRequest = 15
        configuration.waitsForConnectivity = false
        // Our own cache decides what is fresh, and it thinks in days. URLCache
        // holding a second, shorter opinion would only confuse the picture.
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (field, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        // **Without this, restricting the key to this app breaks every
        // lookup.** A Google key limited to "iOS apps" is checked against
        // this header on a plain REST call — only Google's own SDK sends it
        // for you. `docs/places-api.md` says to turn that restriction on
        // before release, and with no header here doing so would have
        // silently ended every geofence and emptied the map.
        if request.headers["X-Goog-Api-Key"] != nil, let bundleID = Bundle.main.bundleIdentifier {
            urlRequest.setValue(bundleID, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }

        let (data, response) = try await session.data(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return HTTPResponse(statusCode: status, body: data)
    }
}

/// Decides which place provider the app runs with.
///
/// A Places key is a billable secret, so it is not in this repository. It comes
/// in as a build setting and lands in the app's Info.plist; see
/// `docs/places-api.md`. With no key the app runs with `EmptyMerchantSource`
/// and says so plainly under Settings > Reminder activity, rather than looking
/// broken for no stated reason.
enum PlacesProvider {

    static let infoPlistKey = "GooglePlacesAPIKey"

    static func makeSource() -> MerchantSource {
        let log = Logger(subsystem: AppLog.subsystem, category: "places")
        guard let key = apiKey else {
            log.notice("no Places API key in the bundle; running with no place provider")
            return EmptyMerchantSource()
        }
        return GooglePlacesSource(
            apiKey: key,
            transport: URLSessionTransport(),
            cache: MerchantCacheStore(fileURL: cacheURL())
        )
    }

    /// The map's source, which is a different object asking a different
    /// question off the same key.
    ///
    /// Deliberately **not** the same instance as `makeSource()`. The geofence
    /// path pays for four fields and caches to disk for a week because it runs
    /// unattended; the map pays for more fields, caches in memory for an hour,
    /// and only runs while somebody is looking at it. Sharing one object would
    /// mean one of those two sets of trade-offs being wrong. See
    /// `PlaceSearchSource`'s doc comment.
    static func makePlaceSearchSource() -> PlaceSearchSource {
        let log = Logger(subsystem: AppLog.subsystem, category: "places")
        guard let key = apiKey else {
            log.notice("no Places API key in the bundle; the map will show location only")
            return EmptyPlaceSearchSource()
        }
        return GooglePlaceSearchSource(
            apiKey: key,
            transport: URLSessionTransport()
        )
    }

    /// XcodeGen substitutes the build setting into the plist, so an unset
    /// setting arrives as an empty string rather than a missing key.
    private static var apiKey: String? {
        let raw = Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func cacheURL() -> URL {
        let directory = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL.temporaryDirectory
        return directory.appendingPathComponent("places-cache.json")
    }
}
