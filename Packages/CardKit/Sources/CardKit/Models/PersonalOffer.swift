import Foundation

public enum PurchaseChannel: String, Codable, CaseIterable, Sendable { case unknown, both, online, inStore }
public enum OfferScope: String, Codable, CaseIterable, Sendable { case merchant, brand, category, partners }
public enum OfferReward: String, Codable, CaseIterable, Sendable { case cashBack, points, credit, spendGet }
public enum OfferRecurrence: String, Codable, CaseIterable, Sendable { case once, monthly, quarterly, annual, unlimited }
public enum OfferStacking: String, Codable, CaseIterable, Sendable { case unknown, addsToStandard, replacesStandard }

/// Account-specific terms, never a catalog entitlement. Amounts are Decimal USD.
/// Matching uses explicit exact aliases; no substring or fuzzy merchant matches.
public struct PersonalOffer: Identifiable, Codable, Hashable, Sendable {
    public var id = UUID()
    public var title = ""
    public var catalogBenefitID: String?
    public var sourceURL: String?
    public var verifiedOn: Date?
    public var scope: OfferScope = .merchant
    public var merchantNames: [String] = []
    public var category: SpendingCategory = .dining
    public var reward: OfferReward = .cashBack
    public var value: Decimal = 0
    public var minimumSpend: Money?
    public var maximumReward: Money?
    public var spendingCap: Money?
    public var startsOn: Date?
    public var expiresOn: Date?
    public var recurrence: OfferRecurrence = .once
    public var channel: PurchaseChannel = .both
    public var enrollmentRequired = false
    public var enrolled = false
    public var stacking: OfferStacking = .unknown
    public var enabled = true
    public var usesPerPeriod = 1
    public var redemptions: [OfferRedemption] = []
    public init() {}

    public var validationError: String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Name this offer." }
        if value.isNaN || value <= 0 || value > 100_000 { return "Enter a reward greater than zero (up to 100,000)." }
        if reward == .cashBack && value > 100 { return "Cash back cannot exceed 100%." }
        if scope != .category && merchantNames.allSatisfy({ Self.normalized($0).isEmpty }) { return "Enter the exact merchant or partner names." }
        if let startsOn, let expiresOn, expiresOn < startsOn { return "Expiration must be after the start date." }
        for amount in [minimumSpend, maximumReward, spendingCap].compactMap({ $0 }) {
            if amount.isNaN || amount <= 0 || amount > 1_000_000 { return "Limits must be positive dollar amounts." }
        }
        if reward == .spendGet && minimumSpend == nil { return "Enter the spend required for this reward." }
        if usesPerPeriod < 1 || usesPerPeriod > 1000 { return "Enter between 1 and 1,000 uses." }
        return nil
    }

    public static func normalized(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    public func matches(_ context: PurchaseContext) -> Bool {
        if scope == .category { return category == context.category }
        guard context.confidence == .exact, let name = context.merchantName else { return false }
        return merchantNames.contains { Self.normalized($0) == Self.normalized(name) }
    }

    public func usage(asOf date: Date) -> [OfferRedemption] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return redemptions.filter { entry in
            guard entry.date <= date else { return false }
            switch recurrence {
            case .once, .unlimited: return true
            case .monthly: return calendar.isDate(entry.date, equalTo: date, toGranularity: .month)
            case .annual: return calendar.isDate(entry.date, equalTo: date, toGranularity: .year)
            case .quarterly: return Quarter.containing(entry.date) == Quarter.containing(date)
            }
        }
    }

    public var summary: String {
        let amount = NSDecimalNumber(decimal: value).stringValue
        let rewardText: String
        switch reward {
        case .cashBack: rewardText = "\(amount)% cash back"
        case .points: rewardText = "\(amount) points per dollar"
        case .credit, .spendGet: rewardText = "$\(amount) credit"
        }
        let whereText = scope == .category ? category.displayName : merchantNames.joined(separator: ", ")
        return "\(rewardText) at \(whereText)"
    }
}

public struct OfferRedemption: Identifiable, Codable, Hashable, Sendable {
    public var id = UUID()
    public var date: Date
    public var purchaseDollars: Money
    /// User-reported received cash value, not independently verified.
    public var receivedDollars: Money
    public init(date: Date = Date(), purchaseDollars: Money, receivedDollars: Money) {
        self.date = date; self.purchaseDollars = purchaseDollars; self.receivedDollars = receivedDollars
    }
}

public struct OfferEvaluation: Sendable, Hashable {
    public var offerID: UUID
    public var estimatedRewardDollars: Money?
    public var centsPerDollar: Double?
    public var explanation: String
}

public enum OfferEvaluator {
    public static func evaluate(_ offer: PersonalOffer, in context: PurchaseContext, centsPerPoint: Double) -> OfferEvaluation? {
        guard offer.enabled, offer.validationError == nil, offer.matches(context),
              offer.startsOn.map({ context.date >= $0 }) ?? true,
              offer.expiresOn.map({ context.date <= $0 }) ?? true else { return nil }
        let usage = offer.usage(asOf: context.date)
        guard offer.recurrence == .unlimited || usage.count < offer.usesPerPeriod else { return nil }
        let spent = usage.reduce(Decimal.zero) { $0 + $1.purchaseDollars }
        let received = usage.reduce(Decimal.zero) { $0 + $1.receivedDollars }
        if let cap = offer.spendingCap, spent >= cap { return nil }
        if let maxReward = offer.maximumReward, received >= maxReward { return nil }
        func conditional(_ reason: String) -> OfferEvaluation {
            OfferEvaluation(offerID: offer.id, estimatedRewardDollars: nil, centsPerDollar: nil,
                            explanation: "\(offer.title): conditional — \(reason)")
        }
        if offer.enrollmentRequired && !offer.enrolled { return conditional("enroll with the issuer first. Saving here does not enroll you.") }
        if offer.channel != .both && offer.channel != context.channel { return conditional("confirm the \(offer.channel.rawValue) purchase channel.") }
        if offer.stacking == .unknown { return conditional("confirm whether this adds to or replaces standard rewards.") }
        guard let purchase = context.purchaseDollars, purchase > 0 else { return conditional("enter the purchase amount to check limits and value.") }
        if let minimum = offer.minimumSpend, purchase < minimum { return conditional("minimum spend is $\(minimum).") }
        let eligible = min(purchase, offer.spendingCap.map { max(0, $0 - spent) } ?? purchase)
        var dollars: Decimal
        switch offer.reward {
        case .cashBack: dollars = eligible * offer.value / 100
        case .points: dollars = eligible * offer.value * Decimal(centsPerPoint) / 100
        case .credit, .spendGet: dollars = min(purchase, offer.value)
        }
        dollars = min(dollars, offer.maximumReward.map { max(0, $0 - received) } ?? dollars)
        dollars = dollars.roundedMoney
        return OfferEvaluation(offerID: offer.id, estimatedRewardDollars: dollars,
                               centsPerDollar: (dollars * 100 / purchase).doubleValue,
                               explanation: "\(offer.title): estimated $\(dollars) from your offer; issuer eligibility still applies.")
    }
}

extension Decimal {
    public var roundedMoney: Decimal {
        var original = self
        var result = Decimal()
        NSDecimalRound(&result, &original, 2, .plain)
        return result
    }
}
