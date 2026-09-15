import Foundation

/// The ranking engine's whole answer about an arrival, not just the half that
/// becomes words.
///
/// **This exists because two engines need the same run.**
/// `RecommendationEngine.decide` throws away the `Recommendation` once it has
/// squeezed a title and a body out of it, which was fine while the only
/// consumer was a notification centre that wanted strings. The notification
/// *policy* needs what was discarded: how many cards were actually in
/// contention, how far ahead the winner was, whether anything is running out.
/// The alternative was re-ranking the wallet a second time in the same
/// millisecond and hoping the two runs agreed.
public struct ArrivalAssessment: Sendable {

    public var decision: ArrivalDecision
    /// Nil only when there was nothing to rank — an empty wallet.
    public var recommendation: Recommendation?
    /// Every card, scored, best first. The count of *distinct* rates in here
    /// is what "is this even a choice" means.
    public var ranked: [CardScore]
    public var context: PurchaseContext

    public init(
        decision: ArrivalDecision,
        recommendation: Recommendation?,
        ranked: [CardScore],
        context: PurchaseContext
    ) {
        self.decision = decision
        self.recommendation = recommendation
        self.ranked = ranked
        self.context = context
    }
}

public extension RecommendationEngine {

    /// `decide`, plus the working.
    ///
    /// Deliberately a superset rather than a replacement: `decide` and
    /// `reminder` stay exactly as they were for the callers that only want
    /// words, and this is the one the notification policy reaches for.
    func assess(
        for arrival: PendingArrival,
        cards: [Card],
        asOf date: Date
    ) -> ArrivalAssessment {
        let context = arrival.merchant.purchaseContext(asOf: date)
        let ranked = rank(cards, in: context)
        return ArrivalAssessment(
            decision: decide(for: arrival, cards: cards, asOf: date),
            recommendation: recommend(from: cards, in: context),
            ranked: ranked,
            context: context
        )
    }
}

public extension NotificationCandidate {

    /// Builds the thing the policy judges out of the thing the engine
    /// produced.
    ///
    /// Returns nil when the ranking engine already said nothing — the policy
    /// only ever narrows, never revives. A candidate the engine refused to
    /// write words for is not a candidate.
    init?(
        merchant: Merchant,
        assessment: ArrivalAssessment,
        movement: ArrivalMovement = .unknown,
        asOf date: Date,
        calendar: Calendar = .current
    ) {
        guard case .send(let reminder, let snapshot) = assessment.decision else { return nil }

        self.init(
            merchantID: merchant.id,
            merchantName: merchant.confidence == .exact ? merchant.name : nil,
            category: merchant.category,
            confidence: merchant.confidence,
            isWeaklyTyped: MerchantCategoryMap.isWeaklyTyped(
                placeTypes: merchant.placeTypes,
                merchantName: merchant.name
            ),
            reminder: reminder,
            snapshot: snapshot,
            competingCardCount: Self.distinctRateCount(in: assessment.ranked),
            edgeCentsPerDollar: Self.edge(in: assessment.ranked),
            expiringInDays: Self.expiringInDays(for: assessment, asOf: date, calendar: calendar),
            movement: movement
        )
    }

    /// How many genuinely different answers the wallet has here.
    ///
    /// **Not `cards.count`, and the difference is the whole point.** Somebody
    /// holding eight cards that all pay 1% everywhere is not choosing between
    /// eight things — they are choosing between one thing, eight times, and a
    /// notification that congratulates them on picking correctly has helped
    /// nobody. Counting distinct rates says "this is a decision" only when
    /// it actually is one.
    ///
    /// Rounded to two decimal places, for the same reason
    /// `RecommendationIdentity` rounds: these are doubles that have been
    /// through point valuation, and two cards that pay identically can differ
    /// in the fifteenth decimal place.
    static func distinctRateCount(in ranked: [CardScore]) -> Int {
        Set(ranked.map { (($0.effectiveCentsPerDollar) * 100).rounded() }).count
    }

    /// The winner's lead over the best *other* card, measured by what each
    /// earns at this till.
    ///
    /// Measured on `effectiveCentsPerDollar` rather than on `total`, which
    /// includes a signup bonus spread over future spend. A bonus is real money
    /// and correctly wins the ranking, but it is not money earned *here*, and
    /// pricing an interruption against a projection would have the app
    /// shouting about a purchase that earns less than the alternative.
    /// **The single-card case is the interesting one.** There is no other card
    /// to measure against, and the two obvious answers are both wrong: zero
    /// prices the only suggestion a wallet can make at nothing, and the full
    /// rate prices it as if the alternative were paying cash, which makes a
    /// lone card score *higher* than a wallet that genuinely has a decision in
    /// it. The comparison that is actually available is against the same card
    /// used anywhere else — what this purchase earns over this card's own base
    /// rate. A 4x dining card is worth three cents a dollar more here than it
    /// is at the hardware shop, and that is a true statement about a real gap.
    static func edge(in ranked: [CardScore]) -> Double {
        guard let best = ranked.first else { return 0 }
        guard let runnerUp = ranked.dropFirst().max(by: {
            $0.effectiveCentsPerDollar < $1.effectiveCentsPerDollar
        }) else {
            let ordinary = best.card.baseRate * best.card.currency.centsPerUnit
            return max(0, best.effectiveCentsPerDollar - ordinary)
        }
        return best.effectiveCentsPerDollar - runnerUp.effectiveCentsPerDollar
    }

    /// Days until something about this suggestion stops being true.
    ///
    /// Two clocks, and the nearer one wins: an open signup bonus's deadline,
    /// and the end of the quarter when the winning rate is a rotating one.
    /// **A permanent 4x dining rate has no clock and must not be given one** —
    /// urgency that is always on is not urgency, it is a permanent bonus to
    /// every score, which is the same as no bonus at all and costs a term.
    static func expiringInDays(
        for assessment: ArrivalAssessment,
        asOf date: Date,
        calendar: Calendar
    ) -> Int? {
        guard let best = assessment.recommendation?.best else { return nil }
        var soonest: Int?

        if let bonus = best.card.welcomeBonus, bonus.isOpen(asOf: date) {
            soonest = bonus.daysRemaining(asOf: date, calendar: calendar)
        }

        if case .rotating(let quarter) = best.source {
            let left = quarter.daysRemaining(asOf: date, calendar: calendar)
            soonest = min(soonest ?? left, left)
        }

        return soonest
    }
}
