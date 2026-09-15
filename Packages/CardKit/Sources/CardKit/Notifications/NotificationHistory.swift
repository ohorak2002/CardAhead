import Foundation

/// What somebody did about a reminder, if anything.
///
/// Three answers, not four, and they are deliberately about *different
/// things*: whether the card got used, whether the app had the place right,
/// and whether the reminder was wanted at all. Collapsing any two of them
/// produces a signal that cannot be acted on — "no" to a suggestion you were
/// glad to get is not the same complaint as "stop telling me about this".
public enum NotificationFeedback: String, Codable, CaseIterable, Sendable, Hashable {

    /// "Used it." The card named was the card paid with.
    case usedIt
    /// "Not here." The app was wrong about where they were, or they had
    /// already left. A signal about *detection*, not about the advice.
    case notHere
    /// "Not useful." The advice was understood and unwanted.
    case notUseful

    public var displayName: String {
        switch self {
        case .usedIt: return "Used it"
        case .notHere: return "Not here"
        case .notUseful: return "Not useful"
        }
    }
}

/// One decision, kept.
///
/// **Suppressions are recorded too, and that is the point.** A history that
/// only holds what was sent can enforce a budget and nothing else: it cannot
/// tell you why you heard nothing all afternoon, which is the single question
/// somebody asks when this feature appears not to work. Every candidate that
/// reaches the decision engine leaves a row.
///
/// **What is deliberately not here.** No coordinate, no address, no dwell
/// time, no arrival or departure. The merchant id is an opaque string from the
/// place provider, kept because a cooldown and a mute are both *about* a
/// specific shop and cannot be enforced without naming one. Rows are pruned
/// aggressively — see `prune(asOf:)` — so this never becomes a record of
/// where somebody has been.
public struct NotificationRecord: Identifiable, Codable, Hashable, Sendable {

    public var id: UUID
    public var date: Date

    public var merchantID: String
    /// Kept only so the debug screen can say which shop; dropped along with
    /// the row. Nil when the place could not be pinned to one business.
    public var merchantName: String?
    public var category: SpendingCategory
    public var cardID: UUID?
    public var cardName: String?

    /// The content identity — see `RecommendationIdentity`. This is what
    /// duplicate suppression compares.
    public var identityKey: String

    public var score: Double
    public var band: NotificationBand
    /// True when it was handed to iOS. False for everything the policy held
    /// back.
    public var wasSent: Bool
    /// Why not, when it was not.
    public var suppression: SuppressionReason?
    /// Filled in if somebody taps one of the actions on the notification.
    public var feedback: NotificationFeedback?
    /// The suggestion this row is about, so feedback can be joined to the
    /// impact ledger.
    public var recommendationID: UUID?

    public init(
        id: UUID = UUID(),
        date: Date,
        merchantID: String,
        merchantName: String? = nil,
        category: SpendingCategory,
        cardID: UUID? = nil,
        cardName: String? = nil,
        identityKey: String,
        score: Double,
        band: NotificationBand,
        wasSent: Bool,
        suppression: SuppressionReason? = nil,
        feedback: NotificationFeedback? = nil,
        recommendationID: UUID? = nil
    ) {
        self.id = id
        self.date = date
        self.merchantID = merchantID
        self.merchantName = merchantName
        self.category = category
        self.cardID = cardID
        self.cardName = cardName
        self.identityKey = identityKey
        self.score = score
        self.band = band
        self.wasSent = wasSent
        self.suppression = suppression
        self.feedback = feedback
        self.recommendationID = recommendationID
    }
}

/// Recent notification decisions, and the questions the policy asks of them.
///
/// **This replaces `ReminderThrottle`, and absorbing it was the point.** The
/// old type answered exactly two questions — how many today, and how many at
/// this shop today — and the moment a third limit was wanted (the same
/// category, the same recommendation, a budget with an override) it would
/// have grown a parallel set of arrays with the same pruning bug in each. One
/// list of rows answers all of them, and answers the debug screen's questions
/// for free.
///
/// Every query takes an explicit date and calendar. Nothing here reads the
/// clock: a policy that cannot be asked "what would you have done at 11pm
/// last Tuesday" is a policy that can only be tested by waiting.
public struct NotificationHistory: Codable, Hashable, Sendable {

    /// Newest last. Pruned on every write.
    public private(set) var records: [NotificationRecord]

    /// How long a row is kept.
    ///
    /// **Four days, which is longer than any cooldown and shorter than a
    /// habit.** The longest window anything asks about is Minimal's
    /// seventy-two-hour merchant cooldown; a day of slack on top covers a row
    /// written at 11:58pm being read just after midnight. Beyond that the row
    /// has no job left, and keeping it would only be building the location
    /// history this type has gone out of its way not to be.
    public static let retention: TimeInterval = 4 * 24 * 3_600

    /// And a hard ceiling, for a day of unusual movement.
    public static let maximumRecords = 200

    public init(records: [NotificationRecord] = []) {
        self.records = records
    }

    // MARK: - Writing

    public mutating func record(_ record: NotificationRecord) {
        records.append(record)
        prune(asOf: record.date)
    }

    /// Attaches somebody's answer to the row it answers. Silently does
    /// nothing if the row has already been pruned, which is the correct
    /// behaviour: a tap on a four-day-old notification has no policy meaning
    /// left.
    public mutating func note(_ feedback: NotificationFeedback, forRecordID id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].feedback = feedback
    }

    /// The row for a suggestion, found by the recommendation it was about —
    /// which is the only identifier a notification carries back into the app.
    public func record(forRecommendationID id: UUID) -> NotificationRecord? {
        records.last { $0.recommendationID == id }
    }

    /// Takes a row back out of the budget.
    ///
    /// Not a deletion: the row stays, so the debug screen can still show that
    /// something was considered, and it stops counting as sent.
    public mutating func markNotSent(recordID id: UUID, reason: SuppressionReason) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].wasSent = false
        records[index].suppression = reason
    }

    public mutating func prune(asOf date: Date) {
        let cutoff = date.addingTimeInterval(-Self.retention)
        records.removeAll { $0.date < cutoff }
        if records.count > Self.maximumRecords {
            records.removeFirst(records.count - Self.maximumRecords)
        }
    }

    public mutating func removeAll() {
        records = []
    }

    // MARK: - Asking

    /// Only what was actually sent counts against a limit. A candidate the
    /// policy held back must not spend the budget it was held back by.
    public var sent: [NotificationRecord] { records.filter(\.wasSent) }

    public func sentCount(on date: Date, calendar: Calendar = .current) -> Int {
        sent.filter { calendar.isDate($0.date, inSameDayAs: date) }.count
    }

    public func lastSent(merchantID: String) -> NotificationRecord? {
        sent.last { $0.merchantID == merchantID }
    }

    public func lastSent(category: SpendingCategory) -> NotificationRecord? {
        sent.last { $0.category == category }
    }

    /// Whether this exact recommendation has already been sent since `date`.
    public func hasSent(identity: RecommendationIdentity, since date: Date) -> Bool {
        sent.contains { $0.identityKey == identity.key && $0.date >= date }
    }

    /// Newest first, for a screen.
    public var newestFirst: [NotificationRecord] { records.reversed() }
}
