import Foundation

/// What a recommendation looked like at the moment it was made, kept so its
/// worth can be worked out later.
///
/// The question "how much was that suggestion actually worth?" can only be
/// answered once somebody says what they spent, and that is hours after the
/// suggestion was made. By then the wallet has moved on: a cap has more spend
/// against it, a quarter has been activated, a card may be gone entirely.
/// Re-running the engine then would answer a different question — what the
/// app *would* say now — and quietly attribute it to a moment it did not
/// happen in.
///
/// So the few numbers the estimate needs are frozen here at the moment of the
/// suggestion. Small on purpose: everything the engine used to rank stays in
/// `CardScore`, and only what a value calculation needs is copied out.
public struct RecommendationSnapshot: Identifiable, Codable, Hashable, Sendable {

    /// Ties every later event — shown, opened, used, priced — back to this one
    /// suggestion.
    public var id: UUID
    public var date: Date

    /// The wallet's own card. Device-local: it means nothing off this phone,
    /// and `ImpactEvent` deliberately does not carry it into anything exported.
    public var cardID: UUID
    /// Which product it is, when the card came from the catalog. This is the
    /// identifier that can answer a question — "Amex Gold" is a card product,
    /// a wallet UUID is a row in somebody's file.
    public var cardProductID: String?
    public var cardName: String

    public var currencyName: String
    public var style: EarnStyle
    /// The rate that actually applied, in the card's own units: 4 for "4x" and
    /// for "4%" alike.
    public var appliedRate: Double
    /// `appliedRate` converted through the user's own valuation, less any fee
    /// abroad. Cents earned per dollar spent.
    public var centsPerDollar: Double

    /// The best *other* card in the wallet, measured the same way. Nil when
    /// there was no other card — with one card there is no alternative, and a
    /// comparison against nothing is not a comparison.
    public var alternateCardName: String?
    public var alternateCentsPerDollar: Double?

    /// The recommended card earns less per dollar here than the alternative,
    /// and won on an open signup bonus instead. The value of the choice is
    /// then progress toward that bonus, not rewards on this purchase, and the
    /// estimate must not pretend otherwise.
    public var wasChosenForWelcomeBonus: Bool

    public var category: SpendingCategory
    public var confidence: MerchantConfidence

    /// Whether the suggestion carried "switch this quarter's bonus on".
    ///
    /// Optional so a ledger written before this was recorded still decodes —
    /// the same pattern as `Card.finish`, and for the same reason. Read it
    /// through `hadActivationNudge`, never directly.
    public var activationNudge: Bool?
    public var capRemainingDollars: Money?
    public var baseCentsPerDollar: Double?
    public var alternateCapRemainingDollars: Money?
    public var alternateBaseCentsPerDollar: Double?
    public var pricedPurchaseDollars: Money?
    public var includesPersonalOffer: Bool?
    public var assumptions: [String]?
    /// Raw standard base rate, before point valuation or foreign fees.
    public var baseAppliedRate: Double?

    /// A missing value in an old file means nobody knows, and nobody knowing
    /// is not the same as it having been there. The safe reading is no.
    public var hadActivationNudge: Bool { activationNudge ?? false }

    public init(
        id: UUID = UUID(),
        date: Date,
        cardID: UUID,
        cardProductID: String?,
        cardName: String,
        currencyName: String,
        style: EarnStyle,
        appliedRate: Double,
        centsPerDollar: Double,
        alternateCardName: String? = nil,
        alternateCentsPerDollar: Double? = nil,
        wasChosenForWelcomeBonus: Bool = false,
        category: SpendingCategory,
        confidence: MerchantConfidence,
        activationNudge: Bool? = nil
    ) {
        self.id = id
        self.date = date
        self.cardID = cardID
        self.cardProductID = cardProductID
        self.cardName = cardName
        self.currencyName = currencyName
        self.style = style
        self.appliedRate = appliedRate
        self.centsPerDollar = centsPerDollar
        self.alternateCardName = alternateCardName
        self.alternateCentsPerDollar = alternateCentsPerDollar
        self.wasChosenForWelcomeBonus = wasChosenForWelcomeBonus
        self.category = category
        self.confidence = confidence
        self.activationNudge = activationNudge
    }

    /// Freezes a recommendation the engine has just produced.
    ///
    /// The runner-up is picked by what it *earns here*, not by where the
    /// ranking put it. Those differ whenever a signup bonus is what won: the
    /// bonus is a projection spread over future spend, and measuring this
    /// purchase against a projection would credit the app with money nobody
    /// has. What the alternative pays at this till is a real number.
    public init(_ recommendation: Recommendation, context: PurchaseContext, id: UUID = UUID()) {
        let best = recommendation.best
        let alternate = recommendation.alternates.max {
            $0.effectiveCentsPerDollar < $1.effectiveCentsPerDollar
        }

        self.init(
            id: id,
            date: context.date,
            cardID: best.card.id,
            cardProductID: best.card.catalogProductID,
            cardName: best.card.displayName,
            currencyName: best.card.currency.name,
            style: best.card.currency.style,
            appliedRate: best.appliedRate,
            centsPerDollar: best.effectiveCentsPerDollar,
            alternateCardName: alternate?.card.displayName,
            alternateCentsPerDollar: alternate?.effectiveCentsPerDollar,
            wasChosenForWelcomeBonus: best.welcomeBonusBoostCentsPerDollar > 0
                && (alternate?.effectiveCentsPerDollar ?? 0) > best.effectiveCentsPerDollar,
            category: context.category,
            confidence: context.confidence,
            activationNudge: recommendation.activationNudge != nil
        )
        capRemainingDollars = best.capRemainingDollars
        baseCentsPerDollar = best.baseCentsPerDollar
        alternateCapRemainingDollars = alternate?.capRemainingDollars
        alternateBaseCentsPerDollar = alternate?.baseCentsPerDollar
        pricedPurchaseDollars = best.pricedPurchaseDollars
        includesPersonalOffer = best.includesPersonalOffer
        assumptions = best.caveats
        baseAppliedRate = best.card.baseRate
    }

    /// One line for the follow-up prompt, naming no merchant.
    ///
    /// Where somebody was is the one thing this app could know and has no
    /// business keeping — see `ImpactEvent`. The card and the kind of shop are
    /// enough for anybody to recognise their own afternoon.
    public var followUpDescription: String {
        "\(cardName) for \(category.displayName.lowercased())"
    }
}
