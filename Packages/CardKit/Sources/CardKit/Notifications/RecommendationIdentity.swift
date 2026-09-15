import Foundation

/// What makes two recommendations *the same recommendation*.
///
/// **The problem this solves is that the engine runs more than once per
/// suggestion.** An arrival is scored on entry, re-scored when the wallet is
/// edited during the dwell, re-scored again if the app wakes for a location
/// fix, and scored afresh on a second visit an hour later. Every one of those
/// produces a brand-new `Recommendation` value with a brand-new
/// `RecommendationSnapshot.id`, so object identity cannot answer "have we
/// already said this?" — by that measure the app has never said anything
/// twice in its life.
///
/// So identity is the *content*: where, what kind of spending, which card,
/// what rate, and whether there is a bonus to switch on. Change any of those
/// and there is genuinely something new to say. Change none of them and
/// saying it again is repeating yourself.
///
/// **The rate is rounded, and that is load-bearing.** It is a `Double` that
/// arrives via point valuation and cap arithmetic, so two runs over an
/// unchanged wallet can differ in the fifteenth decimal place. An identity
/// that moved when the arithmetic jittered would defeat the whole mechanism
/// silently — the app would look like it was deduplicating and never
/// deduplicate anything.
public struct RecommendationIdentity: Codable, Hashable, Sendable, CustomStringConvertible {

    /// A stable, opaque string. Compared, never parsed.
    public let key: String

    public init(
        merchantID: String,
        category: SpendingCategory,
        cardID: UUID,
        appliedRate: Double,
        hasActivationNudge: Bool
    ) {
        let rate = String(format: "%.3f", appliedRate)
        let nudge = hasActivationNudge ? "1" : "0"
        key = "\(merchantID)|\(category.rawValue)|\(cardID.uuidString)|\(rate)|\(nudge)"
    }

    /// Built from what a reminder already carries, so a caller with a decision
    /// in hand does not have to go and find the pieces again.
    public init(merchantID: String, reminder: ArrivalReminder, snapshot: RecommendationSnapshot) {
        self.init(
            merchantID: merchantID,
            category: reminder.category,
            cardID: reminder.cardID,
            appliedRate: snapshot.appliedRate,
            hasActivationNudge: snapshot.hadActivationNudge
        )
    }

    public var description: String { key }
}
