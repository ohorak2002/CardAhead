import SwiftUI
import UIKit
import CardKit

/// The app, as four places rather than one screen with everything pushed onto
/// it.
///
/// **This reverses an earlier decision on purpose, and keeps the reason it was
/// made.** The wallet used to be the whole app, deliberately holding only
/// cards, because a screen with two subjects on it is a screen nobody reads.
/// That principle survives here intact — the Wallet tab is still nothing but
/// cards. What changed is that everything else had been growing a tail of bars
/// and sheets hanging off the bottom of the wallet, and a tab bar is the Apple
/// answer to that: each subject gets its own room, and the wallet gets to stay
/// pure.
///
/// Four is the number. Five is where a tab bar starts to read as a menu, and
/// three would have left Benefits buried somewhere nobody found it.
struct RootTabView: View {

    @Environment(ReminderCenter.self) private var reminders

    @State private var selection: Tab = Tab.launched
    @State private var locationAuth = LocationAuthorization()

    enum Tab: String, Hashable {
        case home, wallet, benefits, more

        /// Home, unless CI asked for something else. See `DemoSeed`.
        ///
        /// "impact" is accepted and lands on More, because Impact is a row
        /// inside More rather than a tab of its own — and pushing it from
        /// there is exactly the route a person takes to it.
        static var launched: Tab {
            guard let raw = DemoSeed.requestedTab else { return .home }
            if raw == "impact" { return .more }
            return Tab(rawValue: raw) ?? .home
        }
    }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                HomeView(auth: locationAuth) { selection = $0 }
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(Tab.home)

            NavigationStack {
                WalletStackView()
            }
            .tabItem { Label("Wallet", systemImage: "creditcard.fill") }
            .tag(Tab.wallet)

            NavigationStack {
                BenefitsBrowserView()
            }
            .tabItem { Label("Benefits", systemImage: "star.fill") }
            .tag(Tab.benefits)

            NavigationStack {
                MoreView(auth: locationAuth, startOnImpact: DemoSeed.requestedTab == "impact")
            }
            .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
            .tag(Tab.more)
        }
        // A reminder names one card, so the tap has to land on the wallet with
        // that card open. Anywhere else and the tap has been wasted.
        .onChange(of: reminders.cardToOpen) { _, id in
            guard id != nil else { return }
            selection = .wallet
        }
    }
}

/// The fourth tab: the things that matter occasionally.
///
/// A list rather than a screen, because every row here is somewhere else. The
/// alternative was a fifth tab, and a five-tab bar reads as a menu — at which
/// point the four things that matter daily stop standing out.
struct MoreView: View {

    @Environment(ImpactStore.self) private var impact
    let auth: LocationAuthorization
    /// Pushes the impact screen straight away rather than waiting for a tap.
    /// Only ever true in a seeded CI run, so a screen two taps deep can still
    /// be photographed — see `DemoSeed`.
    var startOnImpact: Bool = false

    @State private var isShowingImpact = false

    var body: some View {
        VStack(spacing: 0) {
        ScreenHeader("More")
        List {
            Section {
                NavigationLink {
                    ImpactView()
                } label: {
                    Label {
                        HStack {
                            Text("Your impact")
                            Spacer(minLength: Metric.tight)
                            Text(impactSummary)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .foregroundStyle(Color.cardWiseBlue)
                    }
                }
                NavigationLink {
                    WhyThisCardView()
                } label: {
                    Label("Why this card", systemImage: "questionmark.circle")
                }
            } footer: {
                Text("What these reminders have been worth, and how the ranking behind them works.")
            }

            Section {
                NavigationLink {
                    SettingsView(auth: auth)
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        }
        .background(Color(.systemGroupedBackground))
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $isShowingImpact) { ImpactView() }
        .onAppear {
            guard startOnImpact, !isShowingImpact else { return }
            isShowingImpact = true
        }
    }

    private var impactSummary: String {
        guard impact.isRecording else { return "Off" }
        let summary = impact.summary
        guard summary.priced > 0 else { return summary.hasAnythingToShow ? "Nothing priced yet" : "Nothing yet" }
        return String(format: "$%.2f extra", summary.estimatedIncrementalValueCents / 100)
    }
}

#Preview {
    RootTabView()
        .environment(WalletStore.previewStore())
        .environment(ReminderCenter())
        .environment(RegionMonitor())
        .environment(ImpactStore.previewStore())
}
