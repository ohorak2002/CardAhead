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
