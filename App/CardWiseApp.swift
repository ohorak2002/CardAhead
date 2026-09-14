import SwiftUI
import CardKit

@main
struct CardWiseApp: App {

    @State private var store: WalletStore
    @State private var reminders: ReminderCenter
    @State private var monitor: RegionMonitor
    @State private var impact: ImpactStore

    @Environment(\.scenePhase) private var scenePhase

    /// All four are built here rather than lazily on first use, because this
    /// app gets launched in the background — by iOS to hand it a geofence
    /// crossing, and by the user tapping a reminder. Both the location
    /// manager's delegate and the notification centre's have to be in place by
    /// the time launch finishes or the event is dropped, and a background
    /// launch may never evaluate a single view.
    init() {
        // Before anything reads a file. Does nothing at all unless this is a
        // debug build launched with `-CardWiseDemoSeed` — which is how CI
        // photographs screens that have something on them. See `DemoSeed`.
        DemoSeed.install()
        let seeded = DemoSeed.isActive

        let store = WalletStore(fileURL: seeded ? DemoSeed.walletURL() : nil)
        let reminders = ReminderCenter()
        let impact = ImpactStore(fileURL: seeded ? DemoSeed.impactURL() : nil)
        let monitor = RegionMonitor(
            merchantSource: PlacesProvider.makeSource(),
            notifier: reminders,
            stateURL: seeded ? DemoSeed.regionsURL() : nil
        )

        reminders.walletCards = { store.cards }
        reminders.onOpened = { [weak impact] id in impact?.recordOpened(id) }
        monitor.walletCards = { store.cards }
        monitor.impact = impact
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
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(store)
                .environment(reminders)
                .environment(monitor)
                .environment(impact)
                .task { await reminders.refreshStatus() }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    // Cheap and idempotent. Re-checks both permissions, since
                    // either can be changed in Settings behind our back, and
                    // closes the books on any arrival whose few minutes elapsed
                    // while the app was suspended.
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
