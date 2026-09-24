import SwiftUI
import CardKit

@main
struct CardAheadApp: App {

    @State private var store: WalletStore
    @State private var reminders: ReminderCenter
    @State private var monitor: RegionMonitor
    @State private var impact: ImpactStore
    @State private var nearby: NearbyPlacesStore
    @State private var notifications: NotificationPolicyStore
    @State private var organization: OrganizationStore
    /// Not `@State`: it has no observable state to redraw on, and it outlives
    /// every view that reads it. See `EnvironmentValues.placePhotos`.
    private let photos: PlacePhotoLoader

    @Environment(\.scenePhase) private var scenePhase

    /// The first four are built here rather than lazily on first use, because
    /// this app gets launched in the background — by iOS to hand it a geofence
    /// crossing, and by the user tapping a reminder. Both the location
    /// manager's delegate and the notification centre's have to be in place by
    /// the time launch finishes or the event is dropped, and a background
    /// launch may never evaluate a single view.
    init() {
        // Before anything reads a file. Does nothing at all unless this is a
        // debug build launched with `-CardAheadDemoSeed` — which is how CI
        // photographs screens that have something on them. See `DemoSeed`.
        DemoSeed.install()
        let seeded = DemoSeed.isActive

        let store = WalletStore(fileURL: seeded ? DemoSeed.walletURL() : nil)
        let organization = OrganizationStore(fileURL: seeded ? DemoSeed.directory().appendingPathComponent("organization.json") : nil)
        if seeded {
            _ = organization.update { preferences in
                preferences.monthlyGoalDollars = 25
                if let card = store.cards.last { preferences.setNickname("Everyday cash back", for: card.id) }
            }
        }
        let reminders = ReminderCenter()
        let impact = ImpactStore(fileURL: seeded ? DemoSeed.impactURL() : nil)
        let notifications = NotificationPolicyStore(
            fileURL: seeded ? DemoSeed.notificationsURL() : nil
        )
        let monitor = RegionMonitor(
            merchantSource: PlacesProvider.makeSource(),
            notifier: reminders,
            stateURL: seeded ? DemoSeed.regionsURL() : nil
        )

        // The fifth is different: the map only ever runs in the foreground,
        // so it has nothing to be in place for at launch. It is built here
        // anyway because it needs the same wallet closure as the others, and
        // one place that wires everything together beats two.
        // Hoisted out of the call below because two things need it now: the
        // store asks it for places, and the photo loader asks it for the URL
        // of a place's photograph. **The same instance, not two** — the
        // request builder reads the same key, and one object means one place
        // where "is there a provider at all" is decided.
        let placeSource: PlaceSearchSource = seeded
            ? StaticPlaceSearchSource(DemoSeed.places)
            : PlacesProvider.makePlaceSearchSource()

        let nearby = NearbyPlacesStore(
            source: placeSource,
            initialCenter: seeded ? DemoSeed.center : nil
        )
        let photos = PlacePhotoLoader(source: placeSource)

        reminders.walletCards = { store.cards }
        // A tap can launch the app before it has noticed the reminder came
        // due, so the suggestion may not be in the ledger yet. Recording it
        // as shown first is a no-op when it already is, and without it the
        // open — and the "what did you spend?" the tap asks — would find
        // nothing to attach to.
        reminders.onOpened = { [weak impact] id, regionID, deliveredAt in
            impact?.recordShown(regionID: regionID, at: deliveredAt)
            impact?.recordOpened(id)
        }
        // Two ledgers, on purpose. The policy store needs the answer to
        // enforce a mute and to show it on the debug screen; the impact ledger
        // needs it to count whether this app's advice is any use. Neither can
        // read the other's file, and folding them together would put a
        // merchant id into the one structure that refuses to hold one.
        reminders.onFeedback = { [weak impact, weak notifications] id, feedback in
            notifications?.note(feedback, forRecommendationID: id)
            switch feedback {
            case .usedIt: impact?.recordAnswer(.recommendationAccepted, for: id)
            case .notHere: impact?.recordAnswer(.recommendationPlaceRejected, for: id)
            }
        }
        monitor.walletCards = { store.cards }
        nearby.walletCards = { store.cards }
        // The map's "Watching" view reads the geofence plan directly rather
        // than filtering its own results — those are two different sets, and
        // filtering would under-report. See `RegionPlan.watchedPlaces`.
        nearby.watchedPlaces = { [weak monitor] in monitor?.plan?.watchedPlaces ?? [] }
        monitor.impact = impact
        monitor.policy = notifications
        store.onChange = { [weak impact] change in
            switch change {
            case .added(let card): impact?.recordCardAdded(card)
            case .rotatingBonusActivated(let card): impact?.recordRotatingBonusActivated(card)
            }
        }
        monitor.start()

        _store = State(initialValue: store)
        _reminders = State(initialValue: reminders)
        _monitor = State(initialValue: monitor)
        _impact = State(initialValue: impact)
        _nearby = State(initialValue: nearby)
        _notifications = State(initialValue: notifications)
        _organization = State(initialValue: organization)
        self.photos = photos
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(store)
                .environment(reminders)
                .environment(monitor)
                .environment(impact)
                .environment(nearby)
                .environment(notifications)
                .environment(organization)
                .environment(\.placePhotos, photos)
                .task { await reminders.refreshStatus(); ImpactCloudStore.shared.flush() }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    // Cheap and idempotent. Re-checks both permissions, since
                    // either can be changed in Settings behind our back, and
                    // closes the books on any arrival whose few minutes elapsed
                    // while the app was suspended.
                    store.reloadIfLoadFailed()
                    ImpactCloudStore.shared.flush()
                    monitor.start()
                    monitor.settleOutstandingArrivals()
                    Task { await reminders.refreshStatus() }
                }
                .onChange(of: store.cards) { _, _ in
                    monitor.walletDidChange()
                }
        }
    }
}
