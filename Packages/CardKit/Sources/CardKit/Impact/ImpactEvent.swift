import Foundation

/// Something the app did, or something a person did about it.
///
/// **Every kind here has something that actually emits it.** The obvious
/// temptation with an event model is to enumerate everything a product could
/// conceivably measure; the result is a dashboard full of counters that are
/// always zero and nobody can tell which of those are broken and which were
/// never wired up. If a kind is listed below, something in the app raises it.
public enum ImpactEventKind: String, Codable, Sendable, CaseIterable {

    /// The engine had an answer for an arrival and it was handed to iOS.
    case recommendationGenerated
    /// The engine, or a limit above it, decided to stay quiet. See
    /// `SuppressionReason` — this is the count that says whether the app is
    /// interrupting people for nothing.
    case recommendationSuppressed
    /// The dwell completed with the reminder still scheduled, so it reached a
    /// lock screen. The nearest thing to "shown" a local app can honestly
    /// claim: nothing runs at the moment of delivery to confirm it.
    case recommendationShown
    /// Somebody tapped it.
    case recommendationOpened

    /// Somebody said they used the card.
    case recommendationAccepted
    /// Somebody said they did not.
    case recommendationDeclined
    /// Somebody said they could not remember. A real answer and a different
    /// one from silence, which is why it is not folded into either.
    case recommendationUncertain
    /// Nobody answered inside the day it was worth asking about. Raised when
    /// the question expires, so silence is counted rather than forgotten.
    case recommendationIgnored

    /// A spend was volunteered.
    case purchaseAmountEntered
    /// And turned into an estimate. Carries the estimate.
    case estimatedBenefitCalculated

    case cardAdded
    case benefitsViewed
    /// A rotating quarter was switched on in the app.
    case rotatingBonusActivated
}

/// Why the app said nothing. The useful half of the notification story: a
/// product that only counts what it sent cannot tell restraint from silence.
public enum SuppressionReason: String, Codable, Sendable, CaseIterable {
    /// Already reminded about this shop today, or the day's ceiling is spent.
    case throttled
    /// There was no wallet to rank.
    case noCards
    /// Nothing here pays a bonus on any card held, or the best card's lead
    /// over the next one is too small to be worth a lock screen.
    case noMeaningfulEdge
    /// The user left before the dwell completed, so the reminder was pulled.
    case leftEarly

    public var displayName: String {
        switch self {
        case .throttled: return "Already said enough today"
        case .noCards: return "No cards to rank"
        case .noMeaningfulEdge: return "No card was meaningfully better"
        case .leftEarly: return "You left before it was due"
        }
    }
}

/// One line in the ledger.
///
/// **What is deliberately not here.** No merchant name, no merchant id, no
/// coordinate, no street, no card number of any kind, no card id outside this
/// device. The spending category is kept because "dining" is what makes the
/// data answerable; *which* restaurant is what would make it a location
/// history, and the app has no question that needs one. `cardID` is the
/// wallet's own row id — meaningless off this phone, and stripped by
/// `redactedForAnalytics` before an event could ever leave it.
public struct ImpactEvent: Identifiable, Codable, Hashable, Sendable {

    public var id: UUID
    public var kind: ImpactEventKind
    public var date: Date

    /// Ties the events about one suggestion together: generated, shown,
    /// opened, answered, priced.
    public var recommendationID: UUID?

    /// Device-local. See the note above.
    public var cardID: UUID?
    /// The catalog product, when there is one. Nil for a hand-typed card,
    /// which is itself worth knowing: it counts how often the catalog misses.
    public var cardProductID: String?

    public var category: SpendingCategory?
    public var confidence: MerchantConfidence?
    public var suppressionReason: SuppressionReason?
    public var estimate: BenefitEstimate?

    public init(
        id: UUID = UUID(),
        kind: ImpactEventKind,
        date: Date = Date(),
        recommendationID: UUID? = nil,
        cardID: UUID? = nil,
        cardProductID: String? = nil,
        category: SpendingCategory? = nil,
        confidence: MerchantConfidence? = nil,
        suppressionReason: SuppressionReason? = nil,
        estimate: BenefitEstimate? = nil
    ) {
        self.id = id
        self.kind = kind
        self.date = date
        self.recommendationID = recommendationID
        self.cardID = cardID
        self.cardProductID = cardProductID
        self.category = category
        self.confidence = confidence
        self.suppressionReason = suppressionReason
        self.estimate = estimate
    }

    /// The form that may be handed to an `AnalyticsService`.
    ///
    /// Nothing is sent anywhere today — the app ships a no-op service and has
    /// no backend. This exists so that the day one is added, the redaction is
    /// already written, already tested, and not a thing somebody has to
    /// remember to do at the call site.
    ///
    /// Dropped: the wallet's card id, and the card name inside any estimate.
    /// Kept: the product, the category, the confidence, the numbers.
    public func redactedForAnalytics() -> ImpactEvent {
        var copy = self
        copy.cardID = nil
        if var estimate = copy.estimate {
            estimate.cardName = ""
            estimate.comparedWithCardName = estimate.comparedWithCardName.map { _ in "" }
            copy.estimate = estimate
        }
        return copy
    }
}
