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
///   finishes launching — which is why this is built in `CardRewardsApp.init`
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
        }
        plan = nil
        plannedCategories = []
        isMonitoring = false
        save()
        record(.skipped, "Stopped watching. No regions are registered.")
    }

    /// Call after the wallet changes: a new card can make a whole category worth
    /// watching that was not before.
    func walletDidChange() {
        guard isMonitoring else { return }
        guard !walletCards().isEmpty else {
            stop()
            return
        }
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
    func settleOutstandingArrivals(asOf date: Date = Date()) {
        for due in tracker.confirmDue(asOf: date) {
            let minutes = Int(due.confirmAt.timeIntervalSince(due.enteredAt) / 60)
            record(.confirmed, "Still at \(due.merchant.name) after \(minutes) minutes, so a reminder was due.", at: due.confirmAt)
            log.notice("confirmed arrival at \(due.merchant.id, privacy: .public)")
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
        notifier.schedule(arrival)
        save()
        record(.entered, "Arrived at \(monitored.merchant.name). Waiting \(Int(tracker.confirmationDelay / 60)) minutes to be sure.")
        log.notice("entered \(region.identifier, privacy: .public)")
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let cancelled = tracker.exit(regionID: region.identifier, at: Date()) else { return }
        notifier.cancel(regionID: cancelled.regionID)
        save()
        record(.cancelled, "Left \(cancelled.merchant.name) before the reminder was due. Nothing sent.")
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
    private struct StoredState: Codable {
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
