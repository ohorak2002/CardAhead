import SwiftUI
import UIKit
import CardKit

/// The app, as five places rather than one screen with everything pushed onto
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
/// **It was four, and the note here said four was the number** — that five
/// is where a tab bar starts to read as a menu. Map is the fifth, and it is
/// worth the cost: it is the only screen that answers *where*, rather than
/// *which card, here, now*, it needs a map's whole vocabulary of radius and
/// category and search, and there was nowhere to hang it that did not make it
/// a tail on another screen all over again. Five is the ceiling, though, not
/// the new number. The sixth thing goes inside More, like Impact did.
struct RootTabView: View {

    @Environment(ReminderCenter.self) private var reminders

    @State private var selection: Tab = Tab.launched
    @State private var locationAuth = LocationAuthorization()

    enum Tab: String, Hashable {
        case home, map, wallet, benefits, more

        /// Home, unless CI asked for something else. See `DemoSeed`.
        ///
        /// "impact" is accepted and lands on More, because Impact is a row
        /// inside More rather than a tab of its own — and pushing it from
        /// there is exactly the route a person takes to it. "watching" lands
        /// on Map for the same reason: it is a chip on that screen, and
        /// `simctl` cannot tap a chip. "cardphoto" and "cardbenefits" land on
        /// Wallet and open themselves — see `WalletTab`.
        ///
        /// **A name missing from this list silently photographs Home**, which
        /// is exactly what happened the first time the two card-art names were
        /// added to the CI job and not to this switch: a green run, two new
        /// files, and both of them a picture of the wrong screen. Add the name
        /// here in the same commit as the `shoot` line.
        static var launched: Tab {
            guard let raw = DemoSeed.requestedTab else { return .home }
            switch raw {
            case "impact": return .more
            case "watching": return .map
            case "cardphoto", "cardbenefits": return .wallet
            default: return Tab(rawValue: raw) ?? .home
            }
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
                NearbyMapView()
            }
            .tabItem { Label("Map", systemImage: "map.fill") }
            .tag(Tab.map)

            NavigationStack {
                WalletTab()
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

/// The wallet, plus the two card-art screens CI cannot tap its way to.
///
/// Photographing a card and confirming its benefits are both several taps past
/// the wallet, and `simctl` cannot tap — so without this they would be the only
/// screens in the app nobody has ever seen, which is exactly the state the
/// screenshot job exists to end. Same trick as `MoreView(startOnImpact:)`.
///
/// Nothing here is gated on `#if DEBUG` because it does not need to be:
/// `DemoSeed.requestedTab` is already nil in a release build, so both of these
/// stay shut on a real phone.
private struct WalletTab: View {
    @Environment(WalletStore.self) private var store

    @State private var isShowingPhoto = false
    @State private var isShowingBenefits = false

    var body: some View {
        WalletStackView()
            .sheet(isPresented: $isShowingPhoto) { photoScreen }
            .navigationDestination(isPresented: $isShowingBenefits) { benefitsScreen }
            .onAppear {
                isShowingPhoto = DemoSeed.requestedTab == "cardphoto"
                isShowingBenefits = DemoSeed.requestedTab == "cardbenefits"
            }
    }

    @ViewBuilder
    private var photoScreen: some View {
        if let card = store.cards.first {
            CardPhotoView(card: card) { _ in }
        }
    }

    @ViewBuilder
    private var benefitsScreen: some View {
        if let card = store.cards.first {
            CardBenefitsView(mode: .reviewing(card))
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
    /// Read so the impact row can stack its title and its value instead of
    /// drawing them over each other. See the row itself.
    @Environment(\.dynamicTypeSize) private var typeSize
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
                    // **A title and a value on one line stop being one line at
                    // the accessibility text sizes.** An `HStack` with a
                    // `Spacer` between two `Text`s has no answer when neither
                    // half fits: both wrap, the `Spacer` collapses to nothing,
                    // and at the largest size "Your impact" and "$8.47 extra"
                    // were drawn on top of each other — not truncated,
                    // genuinely overlapping and unreadable.
                    //
                    // **The value goes under the whole `Label`, not inside
                    // it.** Stacking the two `Text`s in the label's *title*
                    // slot was the first attempt and it stopped the overlap
                    // without fixing the layout: `Label` lays its title out
                    // beside the icon, so every line after the first wrapped
                    // back to the margin and the value arrived indented under
                    // nothing. A `Label` is allowed to be one thing on one
                    // line; the detail belongs beneath it.
                    if typeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 4) {
                            Label {
                                Text("Your impact")
                            } icon: {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .foregroundStyle(Color.cardWiseBlue)
                            }
                            Text(impactSummary)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
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
        .environment(NearbyPlacesStore())
}
