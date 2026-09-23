import Foundation

/// The words that go on the lock screen, and the card a tap should open.
///
/// Everything here is decided by the ranking engine rather than by whatever is
/// holding the notification API, so the sentence a user reads at a till can be
/// checked in a unit test.
public struct ArrivalReminder: Sendable, Hashable {
    public var title: String
    public var body: String
    /// The card to open when the notification is tapped. A reminder that names
    /// a card and then drops you on a list of them has wasted the tap.
    public var cardID: UUID
    public var cardName: String
    /// Nil when the place could not be pinned down to one business.
    public var merchantName: String?
    public var category: SpendingCategory

    public init(
        title: String,
        body: String,
        cardID: UUID,
        cardName: String,
        merchantName: String?,
        category: SpendingCategory
    ) {
        self.title = title
        self.body = body
        self.cardID = cardID
        self.cardName = cardName
        self.merchantName = merchantName
        self.category = category
    }
}

/// What to do about somebody having arrived somewhere.
///
/// Staying quiet is half the product, so it is half of this type rather than a
/// `nil` that loses the reason. The reason is what lets the app count its own
/// restraint — see `ImpactLedger` — and a product that only counts what it
/// sent cannot tell restraint from silence.
public enum ArrivalDecision: Sendable, Hashable {
    /// The words for the lock screen, and the frozen numbers behind them, so
    /// the suggestion can be priced later if somebody volunteers what they
    /// spent.
    case send(ArrivalReminder, RecommendationSnapshot)
    case stayQuiet(SuppressionReason)

    public var reminder: ArrivalReminder? {
        if case .send(let reminder, _) = self { return reminder }
        return nil
    }

    public var snapshot: RecommendationSnapshot? {
        if case .send(_, let snapshot) = self { return snapshot }
        return nil
    }
}

extension RecommendationEngine {

    /// What to say about an arrival, or why to say nothing.
    ///
    /// Nothing at all is a real answer and the important one. A geofence was
    /// registered here because some card paid a bonus on this category, but by
    /// the time somebody walks in, the cap may be used up or the card may have
    /// been deleted — and a notification that says "use any card, they all pay
    /// the same" is an interruption with no content. Those get dropped.
    public func decide(
        for arrival: PendingArrival,
        cards: [Card],
        asOf date: Date
    ) -> ArrivalDecision {
        let context = arrival.merchant.purchaseContext(asOf: date)
        guard let recommendation = recommend(from: cards, in: context) else {
            return .stayQuiet(.noCards)
        }

        let earnsABonus = recommendation.best.source != .base
            || recommendation.alternates.contains { $0.source != .base }
        guard earnsABonus || recommendation.activationNudge != nil else {
            return .stayQuiet(.noMeaningfulEdge)
        }

        // A win too small to matter is not worth an interruption. An
        // activation nudge is exempt: it is not claiming this card pulls
        // ahead of the others, only that switching a bonus on would pull it
        // ahead of what is currently winning — a different, always-genuine
        // gap that this check has no business judging.
        if recommendation.activationNudge == nil, let runnerUp = recommendation.alternates.first {
            let edge = recommendation.best.total - runnerUp.total
            guard edge >= minimumArrivalEdgeCentsPerDollar else {
                return .stayQuiet(.noMeaningfulEdge)
            }
        }

        let reminder = ArrivalReminder(
            title: recommendation.headline,
            body: body(for: recommendation),
            cardID: recommendation.best.card.id,
            cardName: recommendation.best.card.displayName,
            merchantName: context.merchantName,
            category: context.category
        )
        return .send(reminder, RecommendationSnapshot(recommendation, context: context))
    }

    /// Just the words, for callers that have nothing to do with the reason.
    public func reminder(
        for arrival: PendingArrival,
        cards: [Card],
        asOf date: Date
    ) -> ArrivalReminder? {
        decide(for: arrival, cards: cards, asOf: date).reminder
    }

    /// One sentence for what to do, and one more only when money would
    /// otherwise be lost. A lock screen is not the place for a list.
    ///
    /// The nudge is the *short* form here. On a card screen it explains
    /// itself in full; on a lock screen the full version ran to a third line
    /// and pushed the instruction it was qualifying out of sight.
    ///
    /// **Caveats stay off the lock screen.** This used to add the card's first
    /// one, and for nearly every capped card that was "Cap usage is unknown
    /// for this period. Enter current spend before relying on the bonus." —
    /// two lines of small print under every reminder, which read as a warning
    /// label rather than a tip. The card the tap opens still shows all of them.
    private func body(for recommendation: Recommendation) -> String {
        var sentences = [recommendation.detail]
        if let nudge = recommendation.activationNudge {
            sentences.append(nudge.shortSentence)
        }
        return sentences.joined(separator: " ")
    }
}
