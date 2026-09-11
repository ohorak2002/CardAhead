import Foundation

/// A request, described rather than performed.
///
/// `CardKit` builds these and never sends one. Keeping `URLRequest` out is not
/// fussiness: on Linux it lives in `FoundationNetworking`, and the whole point
/// of this package is that it compiles and tests on Linux CI in seconds. The
/// app adapts these to `URLSession` at the boundary, and the tests adapt them
/// to a canned reply.
public struct HTTPRequest: Hashable, Sendable {
    public var url: URL
    public var method: String
    public var headers: [String: String]
    public var body: Data?

    public init(url: URL, method: String = "GET", headers: [String: String] = [:], body: Data? = nil) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

public struct HTTPResponse: Hashable, Sendable {
    public var statusCode: Int
    public var body: Data

    public init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }

    public var isSuccess: Bool { (200..<300).contains(statusCode) }
}

/// Whatever actually puts the request on the wire.
public protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}
