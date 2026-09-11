import SwiftUI
import CardKit

@main
struct CardRewardsApp: App {

    @State private var store: WalletStore
    @State private var monitor: RegionMonitor

    @Environment(\.scenePhase) private var scenePhase

    /// Both of these are built here rather than lazily on first use, because
    /// iOS relaunches this app in the background to hand it a geofence
    /// crossing, and the location manager's delegate has to be in place by the
    /// time launch finishes or the event is dropped. A background launch may
    /// never evaluate a single view, so nothing load-bearing can wait for one.
    init() {
        let store = WalletStore()
        let monitor = RegionMonitor()
        monitor.walletCards = { store.cards }
        monitor.start()

        _store = State(initialValue: store)
        _monitor = State(initialValue: monitor)
    }

    var body: some Scene {
        WindowGroup {
            WalletStackView()
                .environment(store)
                .environment(monitor)
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    // Cheap and idempotent: re-checks authorization, and picks
                    // up any arrival whose few minutes elapsed while the app
                    // was suspended.
                    monitor.start()
                    monitor.settleOutstandingArrivals()
                }
                .onChange(of: store.cards) { _, _ in
                    monitor.walletDidChange()
                }
        }
    }
}
