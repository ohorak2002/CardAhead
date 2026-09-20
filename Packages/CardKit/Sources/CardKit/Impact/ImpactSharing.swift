import Foundation

/// Allowlisted export schema: no merchant, coordinate, wallet ID, name, or raw event.
public struct SharedImpactRecord: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var recommendation_id: UUID?
    public var day: String
    public var kind: String
    public var category: String?
    public var product: String?
    public var purchase_cents: Int?
    public var estimated_cents: Int?
    public var incremental_cents: Int?
    public var received_cents: Int?
    public var calculation_version: Int?

    public init?(event: ImpactEvent) {
        guard [.recommendationAccepted, .estimatedBenefitCalculated].contains(event.kind) else { return nil }
        id = event.id; recommendation_id = event.recommendationID
        day = Self.day(event.date); kind = event.kind.rawValue
        category = event.category?.rawValue
        product = event.cardProductID.flatMap { CardCatalog.entry(productID: $0)?.productID }
        if let estimate = event.estimate {
            purchase_cents = Self.cents(estimate.purchaseDollars)
            estimated_cents = Self.cents(Decimal(estimate.estimatedValueCents) / 100)
            incremental_cents = estimate.incrementalValueCents.flatMap { Self.cents(Decimal($0) / 100) }
            calculation_version = estimate.calculationVersion
        }
    }
    public init(redemption: OfferRedemption, productID: String?, category: SpendingCategory?) {
        id = redemption.id; day = Self.day(redemption.date); kind = "rewardReceived"
        product = productID.flatMap { CardCatalog.entry(productID: $0)?.productID }
        self.category = category?.rawValue
        received_cents = Self.cents(redemption.receivedDollars)
        // Redemption purchase amount is deliberately omitted: it may already have an estimate.
    }
    public static func day(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    public static func cents(_ amount: Decimal) -> Int? {
        guard !amount.isNaN, abs(amount) <= 1_000_000 else { return nil }
        return NSDecimalNumber(decimal: amount.roundedMoney * 100).intValue
    }
}

/// Persist before transmission; remove only acknowledged IDs. A retry keeps its ID.
public struct ImpactSharingState: Codable, Sendable {
    public private(set) var enabled = false
    public private(set) var consentSince: Date?
    public private(set) var epoch = UUID()
    public private(set) var pending: [SharedImpactRecord] = []
    public private(set) var needsRevocation = false
    public private(set) var needsDeletion = false
    public var accountID: UUID?
    public var retryAfter: Date?
    public var failureCount = 0
    public init() {}
    public mutating func enable(at date: Date = Date()) {
        guard !needsRevocation && !needsDeletion else { return }
        enabled = true; consentSince = date; epoch = UUID()
    }
    public mutating func disable(deletePreviouslyShared: Bool = false) {
        enabled = false; consentSince = nil; pending = []
        epoch = UUID(); needsRevocation = true
        needsDeletion = needsDeletion || deletePreviouslyShared
        retryAfter = nil; failureCount = 0
    }
    public mutating func acknowledgePrivacyChange() { needsRevocation = false; needsDeletion = false }
    public mutating func enqueue(_ record: SharedImpactRecord, createdAt date: Date) {
        guard enabled, let consentSince, date >= consentSince, !pending.contains(where: { $0.id == record.id }) else { return }
        pending.append(record)
    }
    public mutating func acknowledge(_ ids: Set<UUID>, epoch acknowledgedEpoch: UUID) {
        guard enabled, epoch == acknowledgedEpoch else { return }
        pending.removeAll { ids.contains($0.id) }; failureCount = 0; retryAfter = nil
    }
    public mutating func failed(at date: Date = Date()) {
        failureCount = min(failureCount + 1, 10)
        retryAfter = date.addingTimeInterval(min(3600, pow(2, Double(failureCount)) * 5))
    }
}
