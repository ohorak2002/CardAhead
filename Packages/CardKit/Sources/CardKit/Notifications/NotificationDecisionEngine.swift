import Foundation

/// How somebody is moving, as far as anything can tell.
///
/// **Three cases, and `unknown` is the honest default.** Core Location gives
/// the region monitor a speed on a location fix and nothing at all when the
/// app was woken by a geofence with no fix attached, which is most of the
/// time. Rather than build a motion subsystem to fill the gap — a whole
/// framework, a whole permission, for one input to one score — the engine
/// treats "no idea" as neutral and only acts when it genuinely knows.
public enum ArrivalMovement: String, Codable, CaseIterable, Sendable, Hashable {
    /// No usable fix. Scores zero either way.
    case unknown
    /// Stopped, or walking.
    case arrived
    /// Moving at a speed nobody shops at.
    case passingThrough

    /// Above roughly 25 mph nobody is walking into a shop. Below it, a bus, a
    /// slow crawl through a car park and a brisk walk are indistinguishable,
    /// and guessing between them is how an app stops notifying people who are
    /// genuinely there.
    public static let passingThroughMetersPerSecond: Double = 11

    public static func from(speedMetersPerSecond speed: Double?) -> ArrivalMovement {
        // Core Location reports a negative speed when it has none.
        guard let speed, speed >= 0 else { return .unknown }
        return speed >= passingThroughMetersPerSecond ? .passingThrough : .arrived
    }
}

/// Everything the decision engine is allowed to look at.
///
/// Built once, by the caller, from things that already exist — the reminder,
/// the frozen snapshot, the merchant, the wallet. Passing a struct rather than
/// eight arguments is not tidiness: it is what lets a test state a whole
/// situation in one literal and lets the debug screen show what the engine
/// actually saw.
public struct NotificationCandidate: Sendable, Hashable {

    public var merchantID: String
    public var merchantName: String?
    public var category: SpendingCategory
    public var confidence: MerchantConfidence
    /// The category came from a catch-all place type — "food", "shopping_mall"
    /// — rather than from something specific. See
    /// `MerchantCategoryMap.isWeaklyTyped`.
    public var isWeaklyTyped: Bool

    public var reminder: ArrivalReminder
    public var snapshot: RecommendationSnapshot

    /// How many cards in the wallet could plausibly be used here — i.e. how
    /// much of a *choice* the app is helping with. One card is not a choice.
    public var competingCardCount: Int
    /// The winner's lead over the best other card, in cents per dollar. Zero
    /// when there is no other card.
    public var edgeCentsPerDollar: Double
    /// Days until something time-bound about this suggestion runs out: a
    /// rotating quarter ending, a signup bonus closing. Nil when nothing is
    /// on a clock.
    public var expiringInDays: Int?
    public var movement: ArrivalMovement

    public init(
        merchantID: String,
        merchantName: String? = nil,
        category: SpendingCategory,
        confidence: MerchantConfidence,
        isWeaklyTyped: Bool = false,
        reminder: ArrivalReminder,
        snapshot: RecommendationSnapshot,
        competingCardCount: Int,
        edgeCentsPerDollar: Double,
        expiringInDays: Int? = nil,
        movement: ArrivalMovement = .unknown
    ) {
        self.merchantID = merchantID
        self.merchantName = merchantName
        self.category = category
        self.confidence = confidence
        self.isWeaklyTyped = isWeaklyTyped
        self.reminder = reminder
        self.snapshot = snapshot
        self.competingCardCount = competingCardCount
        self.edgeCentsPerDollar = edgeCentsPerDollar
        self.expiringInDays = expiringInDays
        self.movement = movement
    }

    public var identity: RecommendationIdentity {
        RecommendationIdentity(merchantID: merchantID, reminder: reminder, snapshot: snapshot)
    }

    /// See `OpportunityValue` — an internal sort key, never a claim.
    ///
    /// Priced off the *edge*, never off what the winning card earns in total,
    /// for the same reason the impact ledger is: a 4x card earns 4x whether or
    /// not anything told you about it, so what the interruption is worth is
    /// the gap it closes.
    public var estimatedValueCents: Double {
        OpportunityValue.estimatedCents(
            edgeCentsPerDollar: edgeCentsPerDollar,
            category: category
        )
    }
}

/// The answer, with its working shown.
public struct NotificationDecision: Sendable, Hashable {

    public var shouldNotify: Bool
    public var score: NotificationScore
    public var band: NotificationBand
    public var interruption: NotificationInterruption
    /// 0...1, handed straight to `UNNotificationContent.relevanceScore`.
    public var relevance: Double
    public var suppression: SuppressionReason?
    /// When this candidate could succeed, when the answer was "not yet"
    /// rather than "no". Nil for a suppression that time will not fix.
    public var nextEligible: Date?
    /// Whether an exceptional value got this past a spent daily budget.
    public var overrodeBudget: Bool

    public init(
        shouldNotify: Bool,
        score: NotificationScore,
        band: NotificationBand,
        interruption: NotificationInterruption,
        relevance: Double,
        suppression: SuppressionReason? = nil,
        nextEligible: Date? = nil,
        overrodeBudget: Bool = false
    ) {
        self.shouldNotify = shouldNotify
        self.score = score
        self.band = band
        self.interruption = interruption
        self.relevance = relevance
        self.suppression = suppression
        self.nextEligible = nextEligible
        self.overrodeBudget = overrodeBudget
    }
}

/// Whether a recommendation is worth interrupting somebody for.
///
/// **This is the second of two engines and they answer different questions.**
/// `RecommendationEngine` answers *which card is best here* — a question about
/// money, with a right answer. This one answers *is that worth a notification
/// right now* — a question about somebody's attention, with no right answer,
/// only a policy. Keeping them apart is what stops the ranking from quietly
/// acquiring opinions about times of day, and stops the notification policy
/// from acquiring a second opinion about rates.
///
/// **Deterministic, local, and explainable on purpose.** No model, no network,
/// no learned weights. Given the same candidate, history, policy and clock it
/// returns the same decision every time, and the decision carries the
/// arithmetic that produced it. That is what makes it testable at all — and
/// when there is finally a year of real behaviour to learn from, a
/// deterministic baseline is the thing a learned policy would have to beat.
///
/// **Gates first, then the score.** Quiet hours, a muted shop, a switched-off
/// category and a cooldown are not *reasons to score lower* — they are
/// answers on their own, and running the arithmetic anyway would produce a
/// suppression whose stated reason was "scored 42" when the real reason was
/// "it is 3am". The user's own choices are checked before the app's
/// judgement, so a suppression somebody asked for is never reported as the
/// app deciding something was not worth their time.
public struct NotificationDecisionEngine: Sendable {

    public var policy: NotificationPolicy

    public init(policy: NotificationPolicy = NotificationPolicy()) {
        self.policy = policy
    }

    public func decide(
        _ candidate: NotificationCandidate,
        history: NotificationHistory,
        at date: Date,
        calendar: Calendar = .current
    ) -> NotificationDecision {
        let thresholds = policy.thresholds

        // MARK: The user's own instructions, in the order they would expect.

        if !policy.allows(category: candidate.category) {
            return refuse(.categoryDisabled, candidate: candidate, at: date, calendar: calendar)
        }

        if policy.isMuted(merchantID: candidate.merchantID, at: date) {
            return refuse(
                .merchantMuted,
                candidate: candidate,
                at: date,
                calendar: calendar,
                nextEligible: policy.mutedMerchants[candidate.merchantID].flatMap {
                    $0 == .distantFuture ? nil : $0
                }
            )
        }

        if policy.quietHours.contains(date, calendar: calendar) {
            return refuse(
                .quietHours,
                candidate: candidate,
                at: date,
                calendar: calendar,
                nextEligible: policy.quietHours.end(after: date, calendar: calendar)
            )
        }

        // MARK: Repeating itself.

        // Duplicate before cooldown: "you have been told this already" is a
        // more precise complaint than "too soon", and when both are true it is
        // the one worth recording.
        let duplicateWindow = date.addingTimeInterval(-thresholds.merchantCooldown)
        if history.hasSent(identity: candidate.identity, since: duplicateWindow) {
            return refuse(.duplicate, candidate: candidate, at: date, calendar: calendar)
        }

        if let last = history.lastSent(merchantID: candidate.merchantID) {
            let ready = last.date.addingTimeInterval(thresholds.merchantCooldown)
            if date < ready {
                return refuse(
                    .merchantCooldown, candidate: candidate, at: date,
                    calendar: calendar, nextEligible: ready
                )
            }
        }

        if let last = history.lastSent(category: candidate.category) {
            let ready = last.date.addingTimeInterval(thresholds.categoryCooldown)
            if date < ready {
                return refuse(
                    .categoryCooldown, candidate: candidate, at: date,
                    calendar: calendar, nextEligible: ready
                )
            }
        }

        // MARK: Passing through.

        // A hard gate rather than a penalty: somebody doing 40mph past a
        // restaurant is not going to eat there, and no amount of card
        // advantage changes that.
        if candidate.movement == .passingThrough {
            return refuse(.movingTooFast, candidate: candidate, at: date, calendar: calendar)
        }

        // MARK: The arithmetic.

        let score = self.score(candidate, history: history, at: date, calendar: calendar)

        // A place the app cannot identify is one it should not assert things
        // about. Checked against the score rather than as a flat gate, because
        // a vague category plus an enormous, unambiguous win is still worth
        // saying — what must not happen is a *marginal* suggestion attached to
        // a place that might be the wrong one.
        if candidate.confidence == .categoryOnly && candidate.isWeaklyTyped,
           score.total < thresholds.minimumScore + 15 {
            return refuse(
                .lowConfidence, candidate: candidate, at: date,
                calendar: calendar, score: score
            )
        }

        // MARK: The day's budget, and the exception to it.

        // **Before the score bar, and the order is the whole of Example E.**
        // An opportunity valuable enough to break a budget is valuable enough
        // to send, so an override skips the bar rather than meeting it — by
        // the time three notifications have gone out, the "already sent
        // today" penalty has taken twenty-odd points off everything, and a
        // hotel that is genuinely worth twenty dollars would be refused for
        // being the fourth thing said rather than for being unimportant.
        // Nothing above this point is skipped: quiet hours, a mute, a
        // cooldown and a place the app cannot identify all still refuse.
        let spent = history.sentCount(on: date, calendar: calendar)
        if spent >= thresholds.dailyBudget {
            guard candidate.estimatedValueCents >= thresholds.overrideValueCents else {
                return refuse(
                    .dailyBudget, candidate: candidate, at: date, calendar: calendar,
                    score: score, nextEligible: calendar.startOfDay(
                        for: calendar.date(byAdding: .day, value: 1, to: date) ?? date
                    )
                )
            }
            return NotificationDecision(
                shouldNotify: true,
                score: score,
                band: score.band,
                interruption: .active,
                relevance: score.relevance,
                overrodeBudget: true
            )
        }

        guard score.total >= thresholds.minimumScore else {
            return refuse(
                .belowThreshold, candidate: candidate, at: date,
                calendar: calendar, score: score
            )
        }

        return NotificationDecision(
            shouldNotify: true,
            score: score,
            band: score.band,
            interruption: score.band == .passive ? .passive : .active,
            relevance: score.relevance
        )
    }

    // MARK: - Scoring

    /// The weights, in one method, each with the reason it is the size it is.
    ///
    /// Every term is bounded, so no single input can carry a candidate over
    /// the line on its own — the largest, card advantage, tops out at 30 and
    /// Balanced needs 60.
    public func score(
        _ candidate: NotificationCandidate,
        history: NotificationHistory,
        at date: Date,
        calendar: Calendar = .current
    ) -> NotificationScore {
        var score = NotificationScore()

        // **Card advantage, up to 38.** The size of the mistake being
        // prevented, per dollar. Half a cent is the floor the ranking engine
        // already refuses to go below; two cents is a 3% card against a 1%
        // one, and at that point this term is doing all it usefully can.
        let edge = max(0, candidate.edgeCentsPerDollar)
        score.add(
            "Card advantage",
            min(38, edge * 19),
            String(format: "%.1f¢ per $1 over the next best card", edge)
        )

        // **What it is probably worth, up to 26.** Square-rooted rather than
        // linear: the difference between fifteen cents and a dollar matters a
        // great deal, the difference between eighteen dollars and twenty-two
        // does not, and a linear term would let one hotel outweigh every
        // other input combined.
        let valueDollars = candidate.estimatedValueCents / 100
        score.add(
            "Likely value",
            min(26, valueDollars.squareRoot() * 21),
            String(format: "about $%.2f on a typical purchase here", valueDollars)
        )

        // **Whether this is a choice at all: −16 to +22.**
        //
        // The only term that can be negative, and it is the one the brief was
        // most insistent about. One card is not a decision — the app would be
        // telling somebody to use the only card they have — so it does not
        // merely fail to earn points, it *costs* them. Not a gate, though:
        // a single-card wallet with a genuinely large win still clears the
        // bar, which is the difference between "lower priority" and "never".
        let choice: Double
        switch candidate.competingCardCount {
        case ...1: choice = -16
        case 2: choice = 7
        case 3: choice = 17
        default: choice = 22
        }
        score.add(
            "Cards to choose between",
            choice,
            "\(candidate.competingCardCount) card\(candidate.competingCardCount == 1 ? "" : "s") pay\(candidate.competingCardCount == 1 ? "s" : "") differently here"
        )

        // **Urgency, up to 17, and only when it is also relevant.** A credit
        // expiring on Friday is not a reason to interrupt somebody in a car
        // park; it is a reason to say something *at the shop it applies to*,
        // which is where this candidate already is. Relevance is the reason
        // this term exists at all, so it never fires on its own.
        if let days = candidate.expiringInDays {
            let urgency: Double
            switch days {
            case ...3: urgency = 17
            case ...7: urgency = 11
            case ...14: urgency = 5
            default: urgency = 0
            }
            score.add("Running out", urgency, "\(days) day\(days == 1 ? "" : "s") left")
        }

        // **A bonus sitting switched off, 14.** The one case where somebody is
        // about to lose money they already have — see `ActivationNudge`.
        if candidate.snapshot.hadActivationNudge {
            score.add("Bonus not switched on", 14, "activating it would win here")
        }

        // **Confidence, up to 17.** A wrong notification costs more trust than
        // a missed one earns, so being unsure withholds the whole of this term
        // rather than merely trimming it.
        let certainty: Double
        switch (candidate.confidence, candidate.isWeaklyTyped) {
        case (.exact, false): certainty = 17
        case (.exact, true): certainty = 8
        case (.categoryOnly, false): certainty = 6
        case (.categoryOnly, true): certainty = 0
        }
        score.add(
            "Sure where you are",
            certainty,
            candidate.confidence == .exact ? "a specific business" : "the kind of place only"
        )

        // **Actually stopped, 7.** Small, because `unknown` is the common case
        // and a term that mattered would punish everybody the phone happened
        // not to have a fix for.
        if candidate.movement == .arrived {
            score.add("You have stopped", 7)
        }

        // **What has already been said today, −10 each, floored at −28.** The
        // budget is a hard ceiling; this is the slope leading up to it, so the
        // third reminder of the day has to be better than the first was. The
        // floor stops it from zeroing a genuinely large opportunity on its
        // own — that judgement belongs to the budget and its override.
        let spent = history.sentCount(on: date, calendar: calendar)
        if spent > 0 {
            score.add(
                "Already sent today",
                max(-28, Double(spent) * -10),
                "\(spent) notification\(spent == 1 ? "" : "s") so far"
            )
        }

        return score
    }

    // MARK: - Helpers

    private func refuse(
        _ reason: SuppressionReason,
        candidate: NotificationCandidate,
        at date: Date,
        calendar: Calendar,
        score: NotificationScore? = nil,
        nextEligible: Date? = nil
    ) -> NotificationDecision {
        // A gate that fired before the arithmetic still reports a score, so
        // the debug screen has one column rather than a blank. It is the real
        // arithmetic, run for information; nothing was decided by it.
        let scored = score ?? self.score(
            candidate, history: NotificationHistory(), at: date, calendar: calendar
        )
        return NotificationDecision(
            shouldNotify: false,
            score: scored,
            band: .suppress,
            interruption: .passive,
            relevance: 0,
            suppression: reason,
            nextEligible: nextEligible
        )
    }
}
