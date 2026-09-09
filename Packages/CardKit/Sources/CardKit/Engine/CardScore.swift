import Foundation

/// Where the winning rate on a card came from.
public enum RateSource: Sendable, Hashable {
    case base
    case permanent(SpendingCategory)
    case rotating(Quarter)
}

/// One card measured against one purchase. Every number the ranking used is
/// kept here so the UI can explain the choice in a single line.
public struct CardScore: Identifiable, Sendable, Hashable {
    public var id: UUID { card.id }
    public var card: Card

    /// The rate that actually applies, in the card's own units.
    public var appliedRate: Double
    public var source: RateSource
    /// `appliedRate` converted to cents per dollar, minus any foreign transaction fee.
    public var effectiveCentsPerDollar: Double
    /// An open signup bonus expressed as extra cents per dollar of spend.
    public var welcomeBonusBoostCentsPerDollar: Double
    /// What the ranking sorts on.
    public var total: Double

    /// This quarter's rotating categories cover the purchase.
    public var isRotatingMatch: Bool
    /// ...but the user has not clicked activate, so the bonus is not earning.
    public var needsActivation: Bool
    /// The bonus rate was blocked because its cap is used up for the period.
    public var isCapExhausted: Bool

    /// Human-readable, one line: "4x restaurants".
    public var reason: String
    /// Things the user should know before tapping: cap used up, coding quirks, fees.
    public var caveats: [String]

    public var travelPerks: [Perk] {
        card.travelPerks
    }
}
