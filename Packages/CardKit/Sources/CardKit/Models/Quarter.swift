import Foundation

/// A calendar quarter, e.g. 2026-Q3. Rotating bonus programs are keyed to these.
public struct Quarter: Hashable, Sendable, Comparable, CustomStringConvertible {
    public let year: Int
    /// 1 through 4.
    public let index: Int

    public init(year: Int, index: Int) {
        self.year = year
        self.index = min(max(index, 1), 4)
    }

    public var rawValue: String { "\(year)-Q\(index)" }
    public var description: String { rawValue }

    public init?(rawValue: String) {
        let parts = rawValue.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              parts[1].hasPrefix("Q"),
              let index = Int(parts[1].dropFirst()),
              (1...4).contains(index)
        else { return nil }
        self.year = year
        self.index = index
    }

    /// The quarter a date falls in.
    public static func containing(_ date: Date, calendar: Calendar = .current) -> Quarter {
        let components = calendar.dateComponents([.year, .month], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        return Quarter(year: year, index: ((month - 1) / 3) + 1)
    }

    public static func < (lhs: Quarter, rhs: Quarter) -> Bool {
        (lhs.year, lhs.index) < (rhs.year, rhs.index)
    }
}

extension Quarter: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let parsed = Quarter(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a quarter like \"2026-Q3\", got \"\(raw)\""
            )
        }
        self = parsed
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
