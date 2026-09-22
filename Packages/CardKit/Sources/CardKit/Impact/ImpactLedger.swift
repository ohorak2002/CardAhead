import Foundation

/// A suggestion that reached somebody and is not finished with.
public struct OpenRecommendation: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID { snapshot.id }
    public var snapshot: RecommendationSnapshot
    /// When it reached the lock screen, as far as the app can tell.
    public var shownAt: Date
    /// Set once somebody has said whether they used the card.
    ///
    /// An accepted suggestion stays in this list even though the question has
    /// been answered, because the *second*, optional question — what did you
    /// spend — still needs the numbers behind it. This is what stops the first
    /// question being asked again in the meantime.
    public var answeredAt: Date?

    public init(snapshot: RecommendationSnapshot, shownAt: Date, answeredAt: Date? = nil) {
        self.snapshot = snapshot
        self.shownAt = shownAt
        self.answeredAt = answeredAt
    }
}

/// Everything the app knows about whether its own advice was any use.
///
/// A value type with an injected clock, like `ArrivalTracker` and
/// `NotificationHistory` next door, so the rules below are unit tests rather
/// than something only observable by walking around a city for a week.
///
/// **This ledger never leaves the device.** It is written to a file beside the
/// wallet, it is erased with everything else, and there is no service behind
/// it — see `AnalyticsService`, which today is a no-op. What it is *for* is
/// the user's own question, "has this app actually been worth anything to
/// me?", which nobody else can answer for them.
public struct ImpactLedger: Codable, Hashable, Sendable {

    /// Newest last. Capped, because a file that grows forever on a phone is a
    /// bug with a long fuse.
    public private(set) var events: [ImpactEvent]

    /// Suggestions made, kept until they are answered or go stale. Small: one
    /// entry per reminder that is still an open question.
    public private(set) var open: [OpenRecommendation]

    /// How long a suggestion stays worth asking about. Past a day, "did you
    /// use it?" is a memory test, and an answer nobody is sure of is worse
    /// than no answer.
    public var followUpWindow: TimeInterval
    public var maximumEvents: Int

    public init(
        events: [ImpactEvent] = [],
        open: [OpenRecommendation] = [],
        followUpWindow: TimeInterval = 24 * 60 * 60,
        maximumEvents: Int = 500
    ) {
        self.events = events
        self.open = open
        self.followUpWindow = followUpWindow
        self.maximumEvents = maximumEvents
    }

    // MARK: - Writing

    @discardableResult
    public mutating func record(_ event: ImpactEvent) -> ImpactEvent {
        events.append(event)
        if events.count > maximumEvents {
            events.removeFirst(events.count - maximumEvents)
        }
        return event
    }

    /// A reminder was rendered and handed to iOS.
    public mutating func recordGenerated(_ snapshot: RecommendationSnapshot) {
        record(ImpactEvent(
            kind: .recommendationGenerated,
            date: snapshot.date,
            recommendationID: snapshot.id,
            cardID: snapshot.cardID,
            cardProductID: snapshot.cardProductID,
            category: snapshot.category,
            confidence: snapshot.confidence
        ))
    }

    public mutating func recordSuppressed(
        _ reason: SuppressionReason,
        category: SpendingCategory?,
        confidence: MerchantConfidence? = nil,
        at date: Date
    ) {
        record(ImpactEvent(
            kind: .recommendationSuppressed,
            date: date,
            category: category,
            confidence: confidence,
            suppressionReason: reason
        ))
    }

    /// The dwell completed with the reminder still standing, so it is now a
    /// question worth asking the user about later.
    public mutating func recordShown(_ snapshot: RecommendationSnapshot, at date: Date) {
        record(ImpactEvent(
            kind: .recommendationShown,
            date: date,
            recommendationID: snapshot.id,
            cardID: snapshot.cardID,
            cardProductID: snapshot.cardProductID,
            category: snapshot.category,
            confidence: snapshot.confidence
        ))
        open.removeAll { $0.id == snapshot.id }
        open.append(OpenRecommendation(snapshot: snapshot, shownAt: date))
    }

    public mutating func recordOpened(_ recommendationID: UUID, at date: Date) {
        guard let snapshot = snapshot(for: recommendationID) else { return }
        record(ImpactEvent(
            kind: .recommendationOpened,
            date: date,
            recommendationID: snapshot.id,
            cardID: snapshot.cardID,
            cardProductID: snapshot.cardProductID,
            category: snapshot.category,
            confidence: snapshot.confidence
        ))
    }

    /// How somebody answered "did you use it?".
    ///
    /// A no, or a shrug, is a complete answer and closes the suggestion. A yes
    /// only stops the *question* — the suggestion stays here unanswered-for-
    /// pricing, because the second question, what did you spend, is still
    /// unasked and always optional.
    public mutating func recordAnswer(
        _ kind: ImpactEventKind,
        for recommendationID: UUID,
        at date: Date
    ) {
        guard [.recommendationAccepted, .recommendationDeclined, .recommendationUncertain].contains(kind),
              let snapshot = snapshot(for: recommendationID)
        else { return }

        record(ImpactEvent(
            kind: kind,
            date: date,
            recommendationID: snapshot.id,
            cardID: snapshot.cardID,
            cardProductID: snapshot.cardProductID,
            category: snapshot.category,
            confidence: snapshot.confidence
        ))
        if kind == .recommendationAccepted {
            if let index = open.firstIndex(where: { $0.id == recommendationID }) {
                open[index].answeredAt = date
            }
        } else {
            open.removeAll { $0.id == recommendationID }
        }
    }

    /// A spend was volunteered, and priced. Closes the suggestion either way:
    /// somebody who has told the app what they spent has finished with it.
    @discardableResult
    public mutating func recordPurchase(
        _ dollars: Money,
        for recommendationID: UUID,
        at date: Date
    ) -> BenefitEstimate? {
        guard dollars > 0, let snapshot = snapshot(for: recommendationID) else { return nil }
        open.removeAll { $0.id == recommendationID }

        record(ImpactEvent(
            kind: .purchaseAmountEntered,
            date: date,
            recommendationID: snapshot.id,
            cardID: snapshot.cardID,
            cardProductID: snapshot.cardProductID,
            category: snapshot.category,
            confidence: snapshot.confidence
        ))

        guard let estimate = BenefitValueCalculator.estimate(
            for: snapshot,
            purchaseDollars: dollars
        ) else { return nil }

        record(ImpactEvent(
            kind: .estimatedBenefitCalculated,
            date: date,
            recommendationID: snapshot.id,
            cardID: snapshot.cardID,
            cardProductID: snapshot.cardProductID,
            category: snapshot.category,
            confidence: snapshot.confidence,
            estimate: estimate
        ))
        return estimate
    }

    /// Drops suggestions nobody answered inside the window, and records that
    /// they went unanswered — the silence is data, and losing it would flatter
    /// the acceptance rate by only ever counting the people who replied.
    public mutating func expireStale(asOf date: Date) {
        let stale = open.filter { date.timeIntervalSince($0.shownAt) > followUpWindow }
        guard !stale.isEmpty else { return }
        let staleIDs = Set(stale.map(\.id))
        open.removeAll { staleIDs.contains($0.id) }

        for entry in stale where entry.answeredAt == nil {
            let snapshot = entry.snapshot
            record(ImpactEvent(
                kind: .recommendationIgnored,
                date: date,
                recommendationID: snapshot.id,
                cardID: snapshot.cardID,
                cardProductID: snapshot.cardProductID,
                category: snapshot.category,
                confidence: snapshot.confidence
            ))
        }
    }

    // MARK: - Reading

    public func snapshot(for recommendationID: UUID) -> RecommendationSnapshot? {
        open.first { $0.id == recommendationID }?.snapshot
    }

    /// The one suggestion to ask about, or none.
    ///
    /// One, never a queue. A list of "did you use these six?" is a chore, and a
    /// chore is how an optional feature becomes the reason somebody stops
    /// opening an app. The newest is the one they can actually remember.
    public func followUp(asOf date: Date) -> OpenRecommendation? {
        open
            .filter { $0.answeredAt == nil }
            .filter { date.timeIntervalSince($0.shownAt) <= followUpWindow }
            .filter { date >= $0.shownAt }
            .max { $0.shownAt < $1.shownAt }
    }

    public func count(of kind: ImpactEventKind) -> Int {
        events.filter { $0.kind == kind }.count
    }

    public var summary: ImpactSummary { ImpactSummary(self) }

    public mutating func erase() {
        events = []
        open = []
    }
}

/// The ledger added up. Everything a person could reasonably ask about the app
/// they are carrying, and the shape the same questions would take on an
/// aggregate dashboard one day.
public struct ImpactSummary: Hashable, Sendable {

    public var generated: Int
    public var suppressed: Int
    public var shown: Int
    public var opened: Int
    public var accepted: Int
    public var declined: Int
    public var uncertain: Int
    /// Shown, and never answered inside the day it was worth asking about.
    public var ignored: Int
    /// Purchases somebody put a number on.
    public var priced: Int
    public var knownBaselineCount: Int

    /// Summed over user-confirmed estimates only.
    public var estimatedRewardValueCents: Double
    /// The headline, and the honest one: what the *choices* added, over the
    /// best other card in the same wallet.
    public var estimatedIncrementalValueCents: Double

    /// The same incremental figure, split by the kind of shop it came from.
    /// Only categories with something in them; a bar at zero is not a fact
    /// about anybody's spending, it is a gap in what they bothered to log.
    public var incrementalValueByCategory: [SpendingCategory: Double]

    public init(_ ledger: ImpactLedger) {
        generated = ledger.count(of: .recommendationGenerated)
        suppressed = ledger.count(of: .recommendationSuppressed)
        shown = ledger.count(of: .recommendationShown)
        opened = ledger.count(of: .recommendationOpened)
        accepted = ledger.count(of: .recommendationAccepted)
        declined = ledger.count(of: .recommendationDeclined)
        uncertain = ledger.count(of: .recommendationUncertain)
        ignored = ledger.count(of: .recommendationIgnored)

        let priceable = ledger.events.filter { $0.estimate?.isUserConfirmed == true }
        let estimates = priceable.compactMap(\.estimate)
        priced = estimates.count
        knownBaselineCount = estimates.filter { $0.incrementalValueCents != nil }.count
        estimatedRewardValueCents = estimates.reduce(0) { $0 + $1.estimatedValueCents }
        estimatedIncrementalValueCents = estimates.reduce(0) { $0 + ($1.incrementalValueCents ?? 0) }

        var byCategory: [SpendingCategory: Double] = [:]
        for event in priceable {
            guard let category = event.category,
                  let incremental = event.estimate?.incrementalValueCents
            else { continue }
            byCategory[category, default: 0] += incremental
        }
        incrementalValueByCategory = byCategory
    }

    /// Categories with something to show, biggest first — the order the bars
    /// are drawn in.
    public var categoriesByValue: [(category: SpendingCategory, cents: Double)] {
        incrementalValueByCategory
            .filter { $0.value != 0 }
            .sorted { $0.value > $1.value }
            .map { (category: $0.key, cents: $0.value) }
    }

    /// Of the suggestions somebody answered, the share they said they acted
    /// on. Nil until somebody has answered one — a rate over no answers is a
    /// number with nothing behind it, and showing 0% would read as a verdict.
    public var acceptanceRate: Double? {
        let answered = accepted + declined + uncertain
        guard answered > 0 else { return nil }
        return Double(accepted) / Double(answered)
    }

    /// How often the app had the chance to interrupt somebody and did not.
    /// The number that says whether it is a good citizen on a lock screen.
    public var quietRate: Double? {
        let opportunities = generated + suppressed
        guard opportunities > 0 else { return nil }
        return Double(suppressed) / Double(opportunities)
    }

    public var hasAnythingToShow: Bool {
        generated + suppressed + shown + opened > 0
    }
}
