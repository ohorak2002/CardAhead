import Foundation

/// An open signup bonus. While one of these is unmet and unexpired it is
/// usually worth far more per dollar than any category multiplier, which is
/// why the engine converts it into a per-dollar boost rather than a flat nudge.
public struct WelcomeBonus: Codable, Hashable, Sendable {
    /// Payout in the card's reward currency: 60000 points, or 200 for $200 cash back.
    public var rewardUnits: Double
    public var requiredSpendDollars: Money
    public var spentDollars: Money
    public var deadline: Date

    public init(
        rewardUnits: Double,
        requiredSpendDollars: Money,
        spentDollars: Money = 0,
        deadline: Date
    ) {
        self.rewardUnits = rewardUnits
        self.requiredSpendDollars = requiredSpendDollars
        self.spentDollars = spentDollars
        self.deadline = deadline
    }

    public var remainingSpendDollars: Money {
        max(0, requiredSpendDollars - spentDollars)
    }

    public var isMet: Bool { remainingSpendDollars <= 0 }

    public func isExpired(asOf date: Date = Date()) -> Bool { date > deadline }

    public func isOpen(asOf date: Date = Date()) -> Bool { !isMet && !isExpired(asOf: date) }

    public func daysRemaining(asOf date: Date = Date(), calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: date, to: deadline).day ?? 0
    }

    public var fractionComplete: Double {
        guard requiredSpendDollars > 0 else { return 1 }
        return min(1, max(0, (spentDollars / requiredSpendDollars).doubleValue))
    }
}
