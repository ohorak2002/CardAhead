import Foundation

/// How sure we are about *which* business the user walked into.
/// Indoor GPS cannot resolve a single unit in a mall or a food hall, so the
/// engine downgrades the wording rather than naming the wrong restaurant.
public enum MerchantConfidence: String, Codable, Sendable, Hashable {
    case exact
    case categoryOnly
}

/// Everything the engine needs to pick a card. Deliberately holds no location
/// types, so the whole of `CardKit` builds and tests without Core Location.
public struct PurchaseContext: Sendable, Hashable {
    public var category: SpendingCategory
    public var merchantName: String?
    public var confidence: MerchantConfidence
    /// More than ~50 miles from the registered home city.
    public var isTraveling: Bool
    /// Outside the card's home currency, where a foreign transaction fee bites.
    public var isAbroad: Bool
    public var date: Date
    public var purchaseDollars: Money?
    public var channel: PurchaseChannel
    /// Explicit confirmation of issuer-specific restrictions, never inferred from a map type.
    public var confirmedBenefitIDs: Set<String>

    public init(
        category: SpendingCategory,
        merchantName: String? = nil,
        confidence: MerchantConfidence = .exact,
        isTraveling: Bool = false,
        isAbroad: Bool = false,
        date: Date = Date(),
        purchaseDollars: Money? = nil,
        channel: PurchaseChannel = .unknown,
        confirmedBenefitIDs: Set<String> = []
    ) {
        self.category = category
        self.merchantName = merchantName
        self.confidence = confidence
        self.isTraveling = isTraveling
        self.isAbroad = isAbroad
        self.date = date
        self.purchaseDollars = purchaseDollars
        self.channel = channel
        self.confirmedBenefitIDs = confirmedBenefitIDs
    }
}
