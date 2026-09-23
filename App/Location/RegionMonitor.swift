import CoreLocation
import Foundation
import Observation
import os
import CardKit

/// Something worth remembering that happened out of sight.
///
/// None of this feature can be watched happening: the interesting moments occur
/// while the app is suspended, in a shop, with the phone in a pocket. So every
/// one of them is written down, kept, and shown back in Settings. This is the
/// only way anybody — user or developer — finds out what the geofences actually
/// did.
struct RegionEvent: Identifiable, Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case planned, entered, exited, confirmed, cancelled, failed, skipped
    }

    var id = UUID()
    var kind: Kind
    var detail: String
    var date: Date

    var symbolName: String {
        switch kind {
        case .planned: return "mappin.and.ellipse"
        case .entered: return "arrow.down.to.line"
        case .exited: return "arrow.up.forward"
        case .confirmed: return "bell.badge"
        case .cancelled: return "bell.slash"
        case .failed: return "exclamationmark.triangle"
        case .skipped: return "minus.circle"
        }
    }
}

/// Asks iOS to watch the twenty shops nearest the user where one of their cards
/// pays extra, and works out when an entry has lasted long enough to count as
/// having arrived.
///
/// What Apple's documented behaviour gives us, and what the code below leans on:
///
/// - An app may monitor **at most 20** `CLCircularRegion`s. Number 21 fails
///   quietly. `RegionPlanner` owns picking the right twenty.
/// - Region monitoring **relaunches a terminated app** to deliver an entry or
///   exit, so the manager and its delegate must exist by the time the app
///   finishes launching — which is why this is built in `CardWiseApp.init`
///   and not lazily on the first screen that wants it.
/// - Region events need **Always** authorization. With When In Use, iOS accepts
///   the registration but only reports while the app is in the foreground,
///   which is the one moment nobody needs it.
/// - Region monitoring does **not** require a background mode in Info.plist.
///   Only continuous location does, and this deliberately does not use it.
/// - Significant location change wakes the app after roughly 500m of travel.
///   That is the tap on the shoulder that says the twenty may be the wrong
///   twenty now.
///
/// Everything that could be wrong rather than merely unobservable —
/// which shops, in what order, how long a dwell counts, when to redraw —
/// lives in `CardKit` and is unit tested. What is left here is the Core
/// Location plumbing, which cannot be tested without a device.
@Observable
final class RegionMonitor: NSObject, CLLocationManagerDelegate {

    // MARK: - Observable state

    private(set) var plan: RegionPlan?
    private(set) var tracker = ArrivalTracker()
    private(set) var isMonitoring = false
    /// Newest first, capped. Shown in Settings.
    private(set) var recentEvents: [RegionEvent] = []

    var monitoredCount: Int { plan?.regions.count ?? 0 }
    var sourceDescription: String { merchantSource.sourceDescription }

    // MARK: - Collaborators

    private let manager = CLLocationManager()
    private let planner: RegionPlanner
    private let merchantSource: MerchantSource
    private let notifier: ArrivalNotifier
    private let stateURL: URL
    private let log = Logger(subsystem: AppLog.subsystem, category: "regions")

    /// The wallet, read rather than held, so the monitor never has to be told
    /// when a card changes — it asks at the moment it plans.
    @ObservationIgnored var walletCards: () -> [Card] = { [] }

    /// Where suggestions and silences are written down, when anything is.
    /// Optional because every interesting moment here happens whether or not
    /// anybody is counting, and this class must keep working with nothing
    /// attached — a preview, a test, a user who switched recording off.
    @ObservationIgnored var impact: ImpactStore?

    /// Whether a reminder is worth sending, and the record of what has
    /// already been sent.
    ///
    /// **Not optional, unlike `impact`.** Counting is something this class can
    /// do without; deciding is not. With no policy every geofence crossing
    /// would notify, which is the behaviour this whole layer exists to stop,
    /// and a silently-permissive default is the worst possible way to fail.
    @ObservationIgnored var policy = NotificationPolicyStore()

    /// The last location fix, kept only long enough to say whether somebody
    /// is arriving or driving past.
    ///
    /// **A fix and a geofence crossing are two separate wake-ups**, and the
    /// crossing does not carry a location with it. So this is whatever the
    /// most recent fix said, and it is deliberately dropped after a few
    /// minutes: a speed from half an hour ago is not evidence about now, and
    /// `ArrivalMovement.unknown` is a better answer than a stale one.
    @ObservationIgnored private var lastFix: (speed: Double, at: Date)?

    /// How long a speed reading is worth believing.
    private static let fixFreshness: TimeInterval = 180

    /// How far out to ask the place provider for shops. Wider than a geofence
    /// on purpose: twenty candidates within 100m would be a plan that expires
    /// as soon as the user crosses the road.
    @ObservationIgnored var searchRadiusMeters: Double = 2_000

    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var plannedCategories: Set<SpendingCategory> = []

    private static let maximumRememberedEvents = 40

    init(
        planner: RegionPlanner = RegionPlanner(),
        merchantSource: MerchantSource = EmptyMerchantSource(),
        notifier: ArrivalNotifier = LoggingArrivalNotifier(),
        stateURL: URL? = nil
    ) {
        self.planner = planner
        self.merchantSource = merchantSource
        self.notifier = notifier
        self.stateURL = stateURL ?? Self.defaultStateURL()
        super.init()

        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        // The app is woken for a region crossing and has seconds to act. Asking
        // iOS to defer the wake-up until the phone is unlocked would mean
        // missing the entry entirely.
        manager.pausesLocationUpdatesAutomatically = false

        restore()
    }

    // MARK: - Lifecycle

    /// Safe to call on every launch and every foreground.
    func start() {
        guard CLLocationManager.significantLocationChangeMonitoringAvailable() else {
            record(.failed, "This iPhone cannot do significant location change.")
            return
        }
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            record(.failed, "This iPhone cannot monitor regions.")
            return
        }
        guard manager.authorizationStatus == .authorizedAlways else {
            log.notice("not starting: authorization is \(Int(self.manager.authorizationStatus.rawValue), privacy: .public)")
            isMonitoring = false
            return
        }
        // Approximate Location: iOS accepts the regions and never reports a
        // crossing, so registering twenty would be twenty silent promises.
        // Settings and Home say so and point at the switch.
        guard manager.accuracyAuthorization == .fullAccuracy else {
            log.notice("not starting: approximate location, so geofences would never fire")
            if isMonitoring { stop() }
            return
        }

        isMonitoring = true
        manager.startMonitoringSignificantLocationChanges()
        // Significant change can take a while to produce its first fix, and on a
        // fresh install there is no plan at all until one arrives.
        manager.requestLocation()

        // Anything that came due while the app was dead still deserves to be
        // acted on, and anything that never got its exit is dropped here.
        settleOutstandingArrivals()
    }

    /// Gives every region back to iOS. Used when Always is revoked, and when the
    /// wallet is emptied — watching shops for a wallet with no cards in it is
    /// spending someone's battery on nothing.
    func stop() {
        for region in manager.monitoredRegions where RegionPlanner.isOurs(regionID: region.identifier) {
            manager.stopMonitoring(for: region)
        }
        manager.stopMonitoringSignificantLocationChanges()
        for arrival in tracker.dropArrivals(outside: []) {
            notifier.cancel(regionID: arrival.regionID)
            impact?.recordWithdrawn(regionID: arrival.regionID)
        }
        plan = nil
        plannedCategories = []
        isMonitoring = false
        save()
        record(.skipped, "Stopped watching. No regions are registered.")
    }

    /// Call after the wallet changes: a new card can make a whole category worth
    /// watching that was not before, and a card deleted or corrected mid-wait
    /// must not be named on a lock screen four minutes later.
    func walletDidChange() {
        guard isMonitoring else { return }
        guard !walletCards().isEmpty else {
            // stop() already settles and cancels everything pending, which
            // covers refreshing them too — there is nothing left to refresh.
            stop()
            return
        }
        refreshPendingReminders()
        guard let anchor = plan?.anchor else {
            manager.requestLocation()
            return
        }
        // `refresh` already compares the wallet's categories against the ones
        // the plan was drawn for, so a change that does not move a category —
        // pinning a card, renaming one — costs nothing here.
        refresh(around: anchor)
    }

    // MARK: - Planning

    private func refresh(around coordinate: GeoCoordinate, force: Bool = false) {
        let cards = walletCards()
        guard !cards.isEmpty else { return }

        let categories = planner.relevantCategories(in: cards)
        guard !categories.isEmpty else {
            guard plan == nil || plan?.regions.isEmpty == false else { return }
            apply(
                RegionPlan(anchor: coordinate, regions: [], madeAt: Date()),
                categories: [],
                emptyReason: "Every card earns the same rate everywhere, so there is nothing to watch for."
            )
            return
        }

        let stale = force
            || planner.needsRefresh(plan, at: coordinate)
            || categories != plannedCategories
        guard stale else { return }
        guard !isRefreshing else { return }

        isRefreshing = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isRefreshing = false }
            do {
                let merchants = try await self.merchantSource.merchants(
                    near: coordinate,
                    radiusMeters: self.searchRadiusMeters,
                    categories: categories
                )
                let newPlan = self.planner.plan(around: coordinate, merchants: merchants, cards: cards)
                self.apply(newPlan, categories: categories, emptyReason: merchants.isEmpty
                    ? "No nearby shops came back from \(self.merchantSource.sourceDescription.lowercased())."
                    : "None of the \(merchants.count) shops nearby earn a bonus on any of your cards.")
            } catch {
                self.log.error("place lookup failed: \(error.localizedDescription, privacy: .public)")
                self.record(.failed, "Could not look up nearby shops: \(error.localizedDescription)")
            }
        }
    }

    private func apply(_ newPlan: RegionPlan, categories: Set<SpendingCategory>, emptyReason: String) {
        let wanted = Set(newPlan.regions.map(\.id))
        let existing = manager.monitoredRegions.filter { RegionPlanner.isOurs(regionID: $0.identifier) }

        for region in existing where !wanted.contains(region.identifier) {
            manager.stopMonitoring(for: region)
        }

        let alreadyWatched = Set(existing.map(\.identifier))
        for region in newPlan.regions where !alreadyWatched.contains(region.id) {
            manager.startMonitoring(for: circularRegion(for: region))
        }

        // A pending arrival for a region we just gave up can never receive its
        // exit, so it would hang until it went stale.
        for dropped in tracker.dropArrivals(outside: wanted) {
            notifier.cancel(regionID: dropped.regionID)
            impact?.recordWithdrawn(regionID: dropped.regionID)
        }

        plan = newPlan
        plannedCategories = categories
        save()

        if newPlan.regions.isEmpty {
            record(.skipped, emptyReason)
        } else {
            let reach = Int(newPlan.farthestDistanceMeters.rounded())
            let noun = newPlan.regions.count == 1 ? "place" : "places"
            record(.planned, "Watching \(newPlan.regions.count) \(noun) within \(reach)m.")
        }
    }

    private func circularRegion(for region: MonitoredRegion) -> CLCircularRegion {
        // iOS rejects a radius larger than the hardware will track, and silently
        // clamps rather than telling you, so clamp it here where it is visible.
        let radius = min(region.radiusMeters, manager.maximumRegionMonitoringDistance)
        let circular = CLCircularRegion(
            center: CLLocationCoordinate2D(
                latitude: region.merchant.coordinate.latitude,
                longitude: region.merchant.coordinate.longitude
            ),
            radius: radius,
            identifier: region.id
        )
        circular.notifyOnEntry = true
        // Exits matter as much as entries here: an exit is what cancels a
        // reminder for somebody who only walked past.
        circular.notifyOnExit = true
        return circular
    }

    // MARK: - Arrivals

    /// Closes the books on anything whose clock ran out while nobody was
    /// looking. It does not send anything: the reminder was handed to iOS on
    /// the way in and has either fired by now or been cancelled. This is the
    /// bookkeeping that could not happen while the app was dead.
    ///
    /// Each one is logged at the time it actually came due, not at the time we
    /// got round to noticing, or an app opened a week later would claim a week
    /// of arrivals all happened this morning.
    /// Re-renders the notification for every arrival still dwelling, against
    /// the wallet as it stands right now.
    ///
    /// `ReminderCenter.schedule` writes a notification's content once, at
    /// entry, because nothing runs at the moment of delivery to write it
    /// again. This is the other half of that limitation: editing or removing
    /// a card requires the app to be open, which means it *is* running right
    /// now, so every pending arrival gets a fresh chance to say something
    /// correct rather than being left to fire with whatever was true four
    /// minutes ago. `schedule` replaces a pending notification under the same
    /// region id rather than adding a second one, so calling it again here is
    /// exactly a correction, never a duplicate. Does not touch `throttle`:
    /// this is the same reminder being re-rendered, not a new one being sent.
    private func refreshPendingReminders() {
        for arrival in tracker.pending {
            // No policy check here on purpose. This is the *same* reminder
            // being rewritten against an edited wallet, not a new one being
            // sent — running the gates again would suppress it as a duplicate
            // of itself and leave the old, now-wrong words on the lock screen.
            switch notifier.schedule(arrival) {
            case .send(_, let snapshot):
                // A correction, not a second suggestion — `recordGenerated`
                // knows that from the region id and replaces rather than
                // counts again.
                impact?.recordGenerated(snapshot, forRegionID: arrival.regionID)
            case .stayQuiet:
                // The wallet edit took the answer away: the card was removed,
                // or its cap filled in. Nothing will arrive, so the question
                // must not be left waiting for an answer nobody was asked.
                impact?.recordWithdrawn(regionID: arrival.regionID)
            }
        }
    }

    func settleOutstandingArrivals(asOf date: Date = Date()) {
        for due in tracker.confirmDue(asOf: date) {
            let minutes = Int(due.confirmAt.timeIntervalSince(due.enteredAt) / 60)
            record(.confirmed, "Still at \(due.merchant.name) after \(minutes) minutes, so a reminder was due.", at: due.confirmAt)
            log.notice("confirmed arrival at \(due.merchant.id, privacy: .public)")
            // Dated to when it actually came due, not to when the app got
            // round to noticing — the same reason the event above is.
            impact?.recordShown(regionID: due.regionID, at: due.confirmAt)
        }
        save()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways {
            start()
        } else if isMonitoring {
            // Always was taken away. Hand the regions back rather than keep
            // registrations iOS will never fire.
            stop()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coordinate = GeoCoordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        guard coordinate.isValid else { return }

        // Kept for the few minutes it is evidence about anything. See
        // `movement(asOf:)`.
        lastFix = (speed: location.speed, at: location.timestamp)

        // The same wake-up that says "you have moved" is the cheapest moment to
        // notice an arrival whose clock ran out while the app was asleep.
        settleOutstandingArrivals()
        refresh(around: coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard RegionPlanner.isOurs(regionID: region.identifier),
              let monitored = plan?.region(withID: region.identifier)
        else { return }

        guard let arrival = tracker.enter(monitored, at: Date()) else { return }
        record(.entered, "Arrived at \(monitored.merchant.name). Waiting \(Int(tracker.confirmationDelay / 60)) minutes to be sure.")
        log.notice("entered \(region.identifier, privacy: .public)")

        // The dwell is tracked either way — the event log above is honest that
        // an arrival was noticed even on a day the reminder itself is held
        // back. Only the notification is gated.
        evaluate(arrival, merchant: monitored.merchant)
    }

    /// Rank the wallet, judge the result, and send or stay quiet.
    ///
    /// **Both engines, in order, and this is the only place they meet.**
    /// `RecommendationEngine` says which card wins and whether there is
    /// anything worth saying at all; `NotificationDecisionEngine` says whether
    /// that is worth somebody's attention right now. Neither is consulted
    /// anywhere else in this file.
    ///
    /// The decision is recorded either way. A suppression that leaves no trace
    /// is indistinguishable from a bug, and "why did I hear nothing all
    /// afternoon" is the first question anybody asks of this feature.
    private func evaluate(_ arrival: PendingArrival, merchant: Merchant) {
        let when = arrival.confirmAt
        let assessment = RecommendationEngine().assess(
            for: arrival,
            cards: walletCards(),
            asOf: when
        )

        guard let candidate = NotificationCandidate(
            merchant: merchant,
            assessment: assessment,
            movement: movement(asOf: Date()),
            asOf: when
        ) else {
            // The ranking engine had nothing to say. Its own reason is the
            // honest one; the policy never got a look.
            if case .stayQuiet(let reason) = assessment.decision {
                impact?.recordSuppressed(reason, category: merchant.category, at: when)
                record(.skipped, "Nothing worth saying about \(merchant.name): \(reason.displayName.lowercased()).")
            }
            return
        }

        let decision = policy.decide(candidate, at: when)
        policy.record(decision, for: candidate, at: when)

        guard decision.shouldNotify else {
            let reason = decision.suppression ?? .belowThreshold
            impact?.recordSuppressed(reason, category: merchant.category, at: when)
            record(.skipped, "\(reason.displayName) — nothing sent about \(merchant.name).")
            return
        }

        switch notifier.schedule(arrival, decision: decision) {
        case .send(_, let snapshot):
            impact?.recordGenerated(snapshot, forRegionID: arrival.regionID)
            save()
        case .stayQuiet(let reason):
            // The wallet moved between the two runs above. Rare, and the
            // history row already written says it was sent — so correct it
            // rather than leave a lie in the budget.
            policy.markNotSent(recommendationID: candidate.snapshot.id)
            impact?.recordSuppressed(reason, category: merchant.category, at: when)
        }
    }

    /// Arriving, driving past, or no idea.
    private func movement(asOf date: Date) -> ArrivalMovement {
        guard let fix = lastFix, date.timeIntervalSince(fix.at) < Self.fixFreshness else {
            return .unknown
        }
        return ArrivalMovement.from(speedMetersPerSecond: fix.speed)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let cancelled = tracker.exit(regionID: region.identifier, at: Date()) else { return }
        notifier.cancel(regionID: cancelled.regionID)
        save()
        record(.cancelled, "Left \(cancelled.merchant.name) before the reminder was due. Nothing sent.")
        impact?.recordLeftEarly(
            regionID: cancelled.regionID,
            category: cancelled.merchant.category,
            at: Date()
        )
        log.notice("exited \(region.identifier, privacy: .public)")
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        let name = region.flatMap { plan?.region(withID: $0.identifier)?.merchant.name } ?? "a place"
        log.error("monitoring failed for \(region?.identifier ?? "nil", privacy: .public): \(error.localizedDescription, privacy: .public)")
        record(.failed, "iOS refused to watch \(name): \(error.localizedDescription)")
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        log.error("location failed: \(error.localizedDescription, privacy: .public)")
    }

    // MARK: - The event log

    private func record(_ kind: RegionEvent.Kind, _ detail: String, at date: Date = Date()) {
        recentEvents.insert(RegionEvent(kind: kind, detail: detail, date: date), at: 0)
        if recentEvents.count > Self.maximumRememberedEvents {
            recentEvents.removeLast(recentEvents.count - Self.maximumRememberedEvents)
        }
        save()
    }

    func clearEvents() {
        recentEvents = []
        save()
    }

    // MARK: - Persistence

    /// The app is killed between an entry and its confirmation as a matter of
    /// routine, so none of this can live only in memory.
    /// Internal rather than private for exactly one reason: `DemoSeed` writes
    /// one of these so CI can photograph a map that is actually watching
    /// something. Nothing else outside this file may build one — a region
    /// plan that did not come from `RegionPlanner` is a lie about what iOS has
    /// been asked to monitor.
    struct StoredState: Codable {
        var plan: RegionPlan?
        var tracker: ArrivalTracker
        var events: [RegionEvent]
        /// What the wallet made relevant when the plan was drawn, so a card
        /// added while the app was closed is noticed on the next fix.
        var categories: Set<SpendingCategory>
    }

    private static func defaultStateURL() -> URL {
        let directory = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL.temporaryDirectory
        return directory.appendingPathComponent("regions.json")
    }

    private func restore() {
        guard let data = try? Data(contentsOf: stateURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let state = try? decoder.decode(StoredState.self, from: data) else { return }
        plan = state.plan
        tracker = state.tracker
        recentEvents = state.events
        plannedCategories = state.categories
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let state = StoredState(
            plan: plan,
            tracker: tracker,
            events: recentEvents,
            categories: plannedCategories
        )
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: stateURL, options: [.atomic])
    }
}
