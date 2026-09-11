import SwiftUI
import CardKit

@main
struct CardWiseApp: App {

    @State private var store: WalletStore
    @State private var reminders: ReminderCenter
    @State private var monitor: RegionMonitor

    @Environment(\.scenePhase) private var scenePhase

    /// All three are built here rather than lazily on first use, because this
    /// app gets launched in the background — by iOS to hand it a geofence
    /// crossing, and by the user tapping a reminder. Both the location
    /// manager's delegate and the notification centre's have to be in place by
    /// the time launch finishes or the event is dropped, and a background
    /// launch may never evaluate a single view.
    init() {
        let store = WalletStore()
        let reminders = ReminderCenter()
        let monitor = RegionMonitor(
            merchantSource: PlacesProvider.makeSource(),
            notifier: reminders
        )

        reminders.walletCards = { store.cards }
        monitor.walletCards = { store.cards }
        monitor.start()

        _store = State(initialValue: store)
        _reminders = State(initialValue: reminders)
        _monitor = State(initialValue: monitor)
    }

    var body: some Scene {
        WindowGroup {
            WalletStackView()
                .environment(store)
                .environment(reminders)
                .environment(monitor)
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
