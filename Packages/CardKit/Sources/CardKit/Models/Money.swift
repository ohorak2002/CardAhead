import Foundation

/// Dollar amounts use `Decimal` so caps and spend totals do not drift.
/// Earn rates stay `Double` because they are ratios, never balances.
public typealias Money = Decimal

extension Decimal {
    /// Bridge to `Double` for the ratio math in the scoring engine.
    public var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}
