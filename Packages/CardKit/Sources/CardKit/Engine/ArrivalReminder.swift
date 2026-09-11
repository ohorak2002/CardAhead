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

extension RecommendationEngine {

    /// What to say about an arrival, or nothing at all.
    ///
    /// Nothing at all is a real answer and the important one. A geofence was
    /// registered here because some card paid a bonus on this category, but by
    /// the time somebody walks in, the cap may be used up or the card may have
    /// been deleted — and a notification that says "use any card, they all pay
    /// the same" is an interruption with no content. Those get dropped.
    public func reminder(
        for arrival: PendingArrival,
        cards: [Card],
        asOf date: Date
    ) -> ArrivalReminder? {
        let context = arrival.merchant.purchaseContext(asOf: date)
        guard let recommendation = recommend(from: cards, in: context) else { return nil }

        let earnsABonus = recommendation.best.source != .base
            || recommendation.alternates.contains { $0.source != .base }
        guard earnsABonus || recommendation.activationNudge != nil else { return nil }

        // A win too small to matter is not worth an interruption. An
        // activation nudge is exempt: it is not claiming this card pulls
        // ahead of the others, only that switching a bonus on would pull it
        // ahead of what is currently winning — a different, always-genuine
        // gap that this check has no business judging.
        if recommendation.activationNudge == nil, let runnerUp = recommendation.alternates.first {
            let edge = recommendation.best.total - runnerUp.total
            guard edge >= minimumArrivalEdgeCentsPerDollar else { return nil }
        }

        return ArrivalReminder(
            title: recommendation.headline,
            body: body(for: recommendation),
            cardID: recommendation.best.card.id,
            cardName: recommendation.best.card.displayName,
            merchantName: context.merchantName,
            category: context.category
        )
    }

    /// One sentence for what to do, and at most one more for what would
    /// otherwise be lost. A lock screen is not the place for a list.
    private func body(for recommendation: Recommendation) -> String {
        var sentences = [recommendation.detail]
        if let nudge = recommendation.activationNudge {
            sentences.append(nudge)
        } else if let caveat = recommendation.best.caveats.first {
            sentences.append(caveat)
        }
        return sentences.joined(separator: " ")
    }
}
