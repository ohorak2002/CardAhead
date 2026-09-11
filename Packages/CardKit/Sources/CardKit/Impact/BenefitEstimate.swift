import Foundation

/// What a purchase on the recommended card is estimated to have earned, and
/// what choosing that card instead of the next best one is estimated to have
/// added.
///
/// **Every word here is chosen to avoid claiming more than is known.** These
/// are rewards *estimated* to have been earned, using the rate the app
/// believed applied and the user's own idea of what a point is worth. They are
/// not savings. Nothing was discounted, no price was lowered, and no statement
/// was read — this app never sees a transaction. Calling 4x on $85 "$3.40
/// saved" would be three wrong claims in three words, so nothing in this type
/// is called saved.
///
/// The number worth reporting is `incrementalValueCents`: what the *choice*
/// was worth, not what the card was worth. Any card would have earned
/// something. Only the difference is attributable to having been told which
/// one to reach for.
public struct BenefitEstimate: Codable, Hashable, Sendable {

    /// Bumped whenever the arithmetic below changes, so a total summed across
    /// versions can be recognised as such rather than silently mixed.
    public static let currentCalculationVersion = 1

    /// What the user said they spent. Their number, volunteered, never read
    /// from anywhere.
    public var purchaseDollars: Money

    public var cardName: String
    public var currencyName: String
    public var style: EarnStyle
    public var appliedRate: Double

    /// Reward units earned: the rate times the dollars. Points for a card that
    /// earns points; cents of cash back for one that earns a percentage. Kept
    /// in units rather than only in dollars because a point is not a cent and
    /// the app must not quietly decide it is.
    public var rewardUnits: Double

    /// `rewardUnits` valued through `RewardCurrency.centsPerUnit`, which is
    /// whatever the user told Settings a point is worth — one cent unless they
    /// said otherwise. An estimate resting on an estimate, which is why it is
    /// never presented without the word.
    public var estimatedValueCents: Double

    /// The best other card in the wallet, and what it would have earned on the
    /// same purchase. Both nil when the wallet held one card: with nothing to
    /// choose between, the recommendation added nothing and must not be
    /// credited with anything.
    public var comparedWithCardName: String?
    public var comparedWithValueCents: Double?

    /// `estimatedValueCents` less `comparedWithValueCents`. **May be negative**,
    /// and is not clamped: when a signup bonus is what won the ranking, the
    /// recommended card can genuinely earn less at this till than another one
    /// would have. Hiding that would make the total a sales figure rather than
    /// a measurement.
    public var incrementalValueCents: Double?

    /// The recommended card earns less per dollar here and won on an open
    /// signup bonus. The spend still counts toward that bonus, so the choice
    /// is not wrong — but its value lives in a bonus not yet earned, which
    /// this estimate has no way to price.
    public var wasChosenForWelcomeBonus: Bool

    /// True only when a person said they used the card. Everything else in the
    /// ledger is the app's own opinion of what might have happened.
    public var isUserConfirmed: Bool

    public var calculationVersion: Int

    public init(
        purchaseDollars: Money,
        cardName: String,
        currencyName: String,
        style: EarnStyle,
        appliedRate: Double,
        rewardUnits: Double,
        estimatedValueCents: Double,
        comparedWithCardName: String?,
        comparedWithValueCents: Double?,
        incrementalValueCents: Double?,
        wasChosenForWelcomeBonus: Bool,
        isUserConfirmed: Bool,
        calculationVersion: Int = BenefitEstimate.currentCalculationVersion
    ) {
        self.purchaseDollars = purchaseDollars
        self.cardName = cardName
        self.currencyName = currencyName
        self.style = style
        self.appliedRate = appliedRate
        self.rewardUnits = rewardUnits
        self.estimatedValueCents = estimatedValueCents
        self.comparedWithCardName = comparedWithCardName
        self.comparedWithValueCents = comparedWithValueCents
        self.incrementalValueCents = incrementalValueCents
        self.wasChosenForWelcomeBonus = wasChosenForWelcomeBonus
        self.isUserConfirmed = isUserConfirmed
        self.calculationVersion = calculationVersion
    }

    // MARK: - Words for it

    /// "$3.40 cash back", or "$3.40 in Membership Rewards" — the currency is
    /// named for a points card because that dollar figure is only true at the
    /// valuation the user themselves set, and dropping the name would make it
    /// read like money in an account.
    public var rewardSummary: String {
        let dollars = BenefitEstimate.dollars(fromCents: estimatedValueCents)
        if style == .percent {
            return "\(dollars) cash back"
        }
        return "\(dollars) in \(currencyName)"
    }

    /// The sentence the app is allowed to say about the choice itself.
    public var incrementalSummary: String? {
        guard let incremental = incrementalValueCents, let other = comparedWithCardName else { return nil }
        if wasChosenForWelcomeBonus {
            return "\(other) would have earned more here. This went toward the signup bonus instead."
        }
        if incremental <= 0.5 {
            return "\(other) would have earned about the same."
        }
        return "About \(BenefitEstimate.dollars(fromCents: incremental)) more than \(other) would have earned."
    }

    static func dollars(fromCents cents: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let value = NSNumber(value: cents / 100)
        return formatter.string(from: value) ?? String(format: "$%.2f", cents / 100)
    }
}

/// Turns a frozen recommendation and a spend the user volunteered into an
/// estimate. Pure arithmetic, no state, so every rule below is a unit test.
public enum BenefitValueCalculator {

    /// Nil for a purchase of nothing. A zero-dollar estimate is not a small
    /// answer, it is an absence of one, and summing a pile of them into a
    /// "recommendations priced" count would overstate how much is known.
    public static func estimate(
        for snapshot: RecommendationSnapshot,
        purchaseDollars: Money,
        isUserConfirmed: Bool = true
    ) -> BenefitEstimate? {
        guard purchaseDollars > 0 else { return nil }
        let dollars = purchaseDollars.doubleValue

        let value = snapshot.centsPerDollar * dollars
        let alternateValue = snapshot.alternateCentsPerDollar.map { $0 * dollars }

        return BenefitEstimate(
            purchaseDollars: purchaseDollars,
            cardName: snapshot.cardName,
            currencyName: snapshot.currencyName,
            style: snapshot.style,
            appliedRate: snapshot.appliedRate,
            rewardUnits: snapshot.appliedRate * dollars,
            estimatedValueCents: value,
            comparedWithCardName: snapshot.alternateCardName,
            comparedWithValueCents: alternateValue,
            incrementalValueCents: alternateValue.map { value - $0 },
            wasChosenForWelcomeBonus: snapshot.wasChosenForWelcomeBonus,
            isUserConfirmed: isUserConfirmed
        )
    }
}
