import Foundation

/// How a card states its earn rate. Purely presentational: "3%" versus "3x".
public enum EarnStyle: String, Codable, Sendable, Hashable {
    case percent
    case multiplier
}

/// What a card pays in, and what the user thinks one unit is worth.
/// Cash back is one cent per unit by definition. Points are whatever the
/// user says they are, defaulting to one cent so the app never overpromises.
public struct RewardCurrency: Codable, Hashable, Sendable {
    public var name: String
    /// User-editable valuation. 1.0 means one point is worth one cent.
    public var centsPerUnit: Double
    public var style: EarnStyle

    public init(name: String, centsPerUnit: Double = 1.0, style: EarnStyle = .percent) {
        self.name = name
        self.centsPerUnit = centsPerUnit
        self.style = style
    }

    public static let cashBack = RewardCurrency(name: "Cash back", centsPerUnit: 1.0, style: .percent)
    public static let ultimateRewards = RewardCurrency(name: "Ultimate Rewards", centsPerUnit: 1.0, style: .multiplier)
    public static let membershipRewards = RewardCurrency(name: "Membership Rewards", centsPerUnit: 1.0, style: .multiplier)
    public static let capitalOneMiles = RewardCurrency(name: "Capital One miles", centsPerUnit: 1.0, style: .multiplier)

    /// "3%" or "3x", depending on how the issuer states it.
    public func formatted(rate: Double) -> String {
        let number: String
        if rate == rate.rounded() {
            number = String(Int(rate))
        } else {
            number = String(format: "%.1f", rate)
        }
        return style == .percent ? "\(number)%" : "\(number)x"
    }
}
