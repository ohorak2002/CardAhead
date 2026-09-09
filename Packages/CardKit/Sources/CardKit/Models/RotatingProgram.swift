import Foundation

/// One quarter of a rotating bonus program.
public struct RotatingQuarter: Identifiable, Codable, Hashable, Sendable {
    public var id: String { quarter.rawValue }
    public var quarter: Quarter
    public var categories: [SpendingCategory]
    /// Chase Freedom and Discover it both require a manual click each quarter.
    /// Until this is true the bonus rate does not apply, no matter what you buy.
    public var isActivated: Bool
    public var activationDeadline: Date?

    public init(
        quarter: Quarter,
        categories: [SpendingCategory],
        isActivated: Bool = false,
        activationDeadline: Date? = nil
    ) {
        self.quarter = quarter
        self.categories = categories
        self.isActivated = isActivated
        self.activationDeadline = activationDeadline
    }
}

/// The rotating 5% program on cards like Chase Freedom Flex and Discover it.
public struct RotatingProgram: Codable, Hashable, Sendable {
    public var rate: Double
    /// Usually $1,500 of spend per quarter.
    public var cap: EarnCap?
    public var quarters: [RotatingQuarter]

    public init(rate: Double, cap: EarnCap? = nil, quarters: [RotatingQuarter] = []) {
        self.rate = rate
        self.cap = cap
        self.quarters = quarters
    }

    public func quarter(_ quarter: Quarter) -> RotatingQuarter? {
        quarters.first { $0.quarter == quarter }
    }

    /// Quarters that are current or upcoming and still need a click.
    public func unactivatedQuarters(asOf date: Date = Date()) -> [RotatingQuarter] {
        let current = Quarter.containing(date)
        return quarters
            .filter { !$0.isActivated && $0.quarter >= current }
            .sorted { $0.quarter < $1.quarter }
    }
}
