import SwiftUI

@main
struct CardRewardsApp: App {

    @State private var store = WalletStore()

    var body: some Scene {
        WindowGroup {
            WalletStackView()
                .environment(store)
        }
    }
}
