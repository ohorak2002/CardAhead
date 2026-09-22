import Foundation
import Observation
import CardKit

/// Whether this app has been worth carrying, kept on the phone that carries it.
///
/// Local tracking requires no account. A separate, default-off ImpactCloudStore
/// consent controls delivery of a small allowlist of user reports to the backend.
/// The legacy analytics service remains a no-op. Shared deletion is a separate
/// acknowledged server operation; see docs/impact-backend.md.
///
/// Two things it deliberately does not do. It does not read a transaction, a
/// statement or an account — every dollar figure in here is one somebody typed
/// in because they felt like it, and the app is fully useful to somebody who
/// never types one. And it does not record where anybody was: the ledger holds
/// a spending category and never a merchant. The one place a merchant does
/// appear is `openByRegion` below, which is working state, not history.
@Observable
final class ImpactStore {

    private(set) var ledger = ImpactLedger()
    private(set) var receivedRewards: [OfferRedemption] = []

    /// Off means nothing is written down at all, and what was already written
    /// is gone. On alone never grants consent to cloud sharing.
    ///
    /// Set through `setRecording(_:)` rather than by assignment: switching it
    /// off erases, and a property observer that erases is one `load()` away
    /// from erasing the file it has just read.
    private(set) var isRecording = true

    func setRecording(_ on: Bool) {
        guard on != isRecording else { return }
        isRecording = on
        if !on {
            ledger.erase()
            receivedRewards = []
            ImpactCloudStore.shared.setSharing(false)
            openByRegion = [:]
        }
        save()
    }

    /// Suggestions handed to iOS but not yet delivered, by the region whose
    /// geofence started them.
    ///
    /// This is the one structure with a place identifier in it, and it holds
    /// each one for four minutes — the length of the dwell — because the
    /// entry and the confirmation are two separate wakes of a process that is
    /// killed in between, and something has to carry the suggestion across
    /// that gap. `RegionMonitor` already persists the same region ids and the
    /// shops behind them in `regions.json`; nothing new is exposed, and the
    /// entry is dropped the moment the arrival resolves either way.
    @ObservationIgnored private var openByRegion: [String: RecommendationSnapshot] = [:]

    @ObservationIgnored private let analytics: AnalyticsService
    @ObservationIgnored private let fileURL: URL

    init(fileURL: URL? = nil, analytics: AnalyticsService = NoOpAnalyticsService()) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.analytics = analytics
        load()
        // Through `emit`, not straight onto the ledger: expiring a question
        // raises events of its own, and those have to be saved and forwarded
        // like any others.
        emit { $0.expireStale(asOf: Date()) }
    }

    // MARK: - What happened out of sight

    /// A reminder was rendered and handed to iOS.
    ///
    /// Called again for the same region whenever the wallet changes while the
    /// arrival is still dwelling — `RegionMonitor.walletDidChange()` re-renders
    /// pending notifications, and `UNUserNotificationCenter` replaces rather
    /// than stacks them. That is a correction to one suggestion, not a second
    /// suggestion, so the newer numbers replace the older ones and no second
    /// event is raised.
    func recordGenerated(_ snapshot: RecommendationSnapshot, forRegionID regionID: String) {
        guard isRecording else { return }
        let isCorrection = openByRegion[regionID] != nil
        openByRegion[regionID] = snapshot
        guard !isCorrection else { save(); return }
        emit { $0.recordGenerated(snapshot) }
    }

    /// The wallet changed and there is nothing worth saying here any more, so
    /// the notification was pulled. The suggestion that was going to be made
    /// never will be, and must not be waiting for an answer.
    func recordWithdrawn(regionID: String) {
        guard isRecording, openByRegion.removeValue(forKey: regionID) != nil else { return }
        save()
    }

    /// The dwell completed with the reminder still standing, which is as close
    /// to "it reached a lock screen" as an app with no code running at
    /// delivery can honestly get.
    func recordShown(regionID: String, at date: Date) {
        guard isRecording, let snapshot = openByRegion.removeValue(forKey: regionID) else { return }
        emit { $0.recordShown(snapshot, at: date) }
    }

    /// Left before the reminder was due, or the region was dropped from the
    /// plan. Counted as restraint, because it is: nothing reached anybody.
    func recordLeftEarly(regionID: String, category: SpendingCategory?, at date: Date) {
        guard isRecording, openByRegion.removeValue(forKey: regionID) != nil else { return }
        emit { $0.recordSuppressed(.leftEarly, category: category, at: date) }
    }

    func recordSuppressed(
        _ reason: SuppressionReason,
        category: SpendingCategory?,
        at date: Date = Date()
    ) {
        guard isRecording else { return }
        emit { $0.recordSuppressed(reason, category: category, at: date) }
    }

    func recordOpened(_ recommendationID: UUID, at date: Date = Date()) {
        guard isRecording else { return }
        emit { $0.recordOpened(recommendationID, at: date) }
    }

    // MARK: - What the user says about it

    func recordUsedRecommendation(_ snapshot: RecommendationSnapshot, purchase: Money?) {
        guard isRecording else { return }
        let date = Date()
        emit {
            $0.recordGenerated(snapshot)
            $0.recordShown(snapshot, at: date)
            $0.recordAnswer(.recommendationAccepted, for: snapshot.id, at: date)
            if let purchase, purchase > 0 { $0.recordPurchase(purchase, for: snapshot.id, at: date) }
        }
    }

    /// The one suggestion worth asking about, if there is one.
    var followUp: OpenRecommendation? {
        guard isRecording else { return nil }
        return ledger.followUp(asOf: Date())
    }

    func recordAnswer(_ kind: ImpactEventKind, for recommendationID: UUID, at date: Date = Date()) {
        guard isRecording else { return }
        emit { $0.recordAnswer(kind, for: recommendationID, at: date) }
    }

    @discardableResult
    func recordPurchase(_ dollars: Money, for recommendationID: UUID, at date: Date = Date()) -> BenefitEstimate? {
        guard isRecording else { return nil }
        var estimate: BenefitEstimate?
        emit { estimate = $0.recordPurchase(dollars, for: recommendationID, at: date) }
        return estimate
    }

    func recordReceived(_ redemption: OfferRedemption, productID: String?, category: SpendingCategory?) {
        guard isRecording else { return }
        receivedRewards.append(redemption)
        ImpactCloudStore.shared.receive(redemption, productID: productID, category: category)
        save()
    }

    // MARK: - What happens in the app

    func recordCardAdded(_ card: Card) {
        record(.cardAdded, card: card)
    }

    func recordBenefitsViewed(_ card: Card) {
        record(.benefitsViewed, card: card)
    }

    func recordRotatingBonusActivated(_ card: Card) {
        record(.rotatingBonusActivated, card: card)
    }

    /// Somebody muted a place or switched a whole category off.
    ///
    /// **The category is carried and the place never is.** Which *kind* of
    /// shop somebody stopped wanting to hear about is the answerable question
    /// — it says the policy is wrong about a category. *Which* shop is the
    /// one thing this ledger has always refused to hold, and muting one is
    /// not a reason to start.
    func recordSilenced(category: SpendingCategory? = nil, at date: Date = Date()) {
        guard isRecording else { return }
        emit {
            $0.record(ImpactEvent(kind: .recommendationsSilenced, date: date, category: category))
        }
    }

    private func record(_ kind: ImpactEventKind, card: Card) {
        guard isRecording else { return }
        emit {
            $0.record(ImpactEvent(
                kind: kind,
                cardID: card.id,
                cardProductID: card.catalogProductID
            ))
        }
    }

    // MARK: - Reading

    var summary: ImpactSummary { ledger.summary }

    func erase() {
        ledger.erase()
        receivedRewards = []
        ImpactCloudStore.shared.deleteShared()
        openByRegion = [:]
        save()
    }

    // MARK: - Writing it down

    /// Every mutation goes through here, so there is exactly one place that
    /// decides what the analytics service is shown — the redacted event, never
    /// the one in the ledger. A call site cannot forget what it never had to
    /// remember.
    private func emit(_ change: (inout ImpactLedger) -> Void) {
        // Not a count: at the ledger's cap, appending one event also drops one
        // off the front, so the count never moves and a count-based diff would
        // silently forward nothing for the rest of the app's life. The last
        // event before the change is a fixed point — the cap only ever trims
        // from the old end.
        let previousLast = ledger.events.last?.id
        change(&ledger)

        let new: ArraySlice<ImpactEvent>
        if let previousLast, let index = ledger.events.lastIndex(where: { $0.id == previousLast }) {
            new = ledger.events[ledger.events.index(after: index)...]
        } else {
            new = ledger.events[...]
        }
        for event in new {
            analytics.record(event.redactedForAnalytics())
            ImpactCloudStore.shared.receive(event)
        }
        save()
    }

    private static func defaultFileURL() -> URL {
        let directory = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL.temporaryDirectory
        return directory.appendingPathComponent("impact.json")
    }

    private struct StoredState: Codable {
        var ledger: ImpactLedger
        var openByRegion: [String: RecommendationSnapshot]
        /// Optional so a file written before the switch existed still decodes
        /// — see `Card.finish` for the same pattern. Missing means on, which
        /// is what it was.
        var isRecording: Bool?
        var receivedRewards: [OfferRedemption]?
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let state = try? decoder.decode(StoredState.self, from: data) else { return }
        isRecording = state.isRecording ?? true
        guard isRecording else { return }
        ledger = state.ledger
        receivedRewards = state.receivedRewards ?? []
        openByRegion = state.openByRegion
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let state = StoredState(ledger: ledger, openByRegion: openByRegion, isRecording: isRecording, receivedRewards: receivedRewards)
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}

extension ImpactStore {
    /// Pointed at a throwaway file, so a preview cannot write into the real
    /// ledger. Matches `WalletStore.previewStore()`.
    static func previewStore() -> ImpactStore {
        ImpactStore(fileURL: URL.temporaryDirectory.appendingPathComponent("preview-impact.json"))
    }
}
