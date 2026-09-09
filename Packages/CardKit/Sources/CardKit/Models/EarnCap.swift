import Foundation

public enum CapPeriod: String, Codable, Sendable, Hashable {
    case monthly, quarterly, annual

    public var displayName: String {
        switch self {
        case .monthly: return "per month"
        case .quarterly: return "per quarter"
        case .annual: return "per year"
        }
    }
}

/// A ceiling on how much spend earns the bonus rate, e.g. Amex Blue Cash
/// Preferred's $6,000 a year at U.S. supermarkets.
public struct EarnCap: Codable, Hashable, Sendable {
    public var limitDollars: Money
    public var period: CapPeriod
    /// How much of the cap the user has already burned this period.
    /// The user edits this; v1 has no transaction feed to fill it in.
    public var spentDollars: Money

    public init(limitDollars: Money, period: CapPeriod, spentDollars: Money = 0) {
        self.limitDollars = limitDollars
        self.period = period
        self.spentDollars = spentDollars
    }

    public var remainingDollars: Money {
        max(0, limitDollars - spentDollars)
    }

    public var isExhausted: Bool {
        remainingDollars <= 0
    }

    /// Fraction of the cap used, 0...1. Drives the progress bar in the card detail view.
    public var fractionUsed: Double {
        guard limitDollars > 0 else { return 0 }
        return min(1, max(0, (spentDollars / limitDollars).doubleValue))
    }

    public func resetForNewPeriod() -> EarnCap {
        EarnCap(limitDollars: limitDollars, period: period, spentDollars: 0)
    }
}
