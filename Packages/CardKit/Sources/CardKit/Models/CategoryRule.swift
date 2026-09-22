import Foundation

/// One permanent earn rule on a card: "3% dining", "4x U.S. supermarkets".
public struct CategoryRule: Identifiable, Codable, Hashable, Sendable {
    /// A card carries at most one permanent rule per category, so the category
    /// is a stable identity without storing a UUID we would have to migrate.
    public var id: SpendingCategory { category }

    public var category: SpendingCategory
    /// Multiplier in the card's own reward currency.
    /// 5% cash back is `5.0`. 4x points is `4.0`.
    public var rate: Double
    public var cap: EarnCap?
    /// Shown in the card detail view. Used for coding quirks the user should know about.
    public var note: String?
    public var merchantNames: [String]?
    public var requiresConfirmation: Bool?

    public init(category: SpendingCategory, rate: Double, cap: EarnCap? = nil, note: String? = nil, merchantNames: [String]? = nil, requiresConfirmation: Bool? = nil) {
        self.category = category
        self.rate = rate
        self.cap = cap
        self.note = note
        self.merchantNames = merchantNames
        self.requiresConfirmation = requiresConfirmation
    }
}
