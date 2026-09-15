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
            // All three are the Map tab: "watching" is a chip on it,
            // "placecard" selects a pin, and "placedetail" opens one. None of
            // the three is reachable by `simctl`, which cannot tap.
            case "watching", "placecard", "placedetail": return .map
            case "cardphoto", "cardbenefits", "cardpreview", "carddetail", "addcard": return .wallet
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
    @State private var isShowingPreview = false

    var body: some View {
        WalletStackView()
            .sheet(isPresented: $isShowingPhoto) { photoScreen }
            .navigationDestination(isPresented: $isShowingBenefits) { benefitsScreen }
            .navigationDestination(isPresented: $isShowingPreview) { previewScreen }
            .onAppear {
                isShowingPhoto = DemoSeed.requestedTab == "cardphoto"
                isShowingBenefits = DemoSeed.requestedTab == "cardbenefits"
                isShowingPreview = DemoSeed.requestedTab == "cardpreview"
            }
    }

    @ViewBuilder
    private var photoScreen: some View {
        if let card = store.cards.first {
            CardPhotoView(card: card) { _ in }
        }
    }

    /// **Pushed straight onto the wallet, which is not where it really
    /// lives.** The preview is three taps inside a sheet — add, pick a bank,
    /// pick a product — and `simctl` cannot tap any of them. Photographing the
    /// screen is the point; photographing the route to it is not something CI
    /// can do either way.
    @ViewBuilder
    private var previewScreen: some View {
        if let entry = CardCatalog.entries.first {
            CardPreviewView(entry: entry, onFinish: {})
        }
    }

    @ViewBuilder
    private var benefitsScreen: some View {
        if let card = store.cards.first {
            CardBenefitsView(mode: .reviewing(card), presentation: .pushed)
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
        ScreenHeader("More", subtitle: "Everything that is not a card")
        List {
            // **The impact is a card, not a row.** This screen was three grey
            // rows and 386 points — 44% of the phone — of empty background
            // under them. The fix is not furniture to pad it out; it is
            // giving the one genuinely valuable thing on it the weight it
            // should have had. A number somebody wants to look at does not
            // belong in the same typeface as "Settings".
            //
            // It also retires the Dynamic Type workaround that used to live
            // here. A title and a value fighting over one line needed a
            // special case at the accessibility sizes; stacked in a card they
            // were never on one line to begin with.
            Section {
                impactCard
            }

            Section {
                NavigationLink {
                    WhyThisCardView()
                } label: {
                    Label("Why this card", systemImage: "questionmark.circle")
                }
                NavigationLink {
                    SettingsView(auth: auth)
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            } footer: {
                Text("How the ranking behind these reminders works, and everything else.")
            }

        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        // **Pinned to the bottom, not trailing the last section.** As a
        // `Section` footer it sat wherever the list happened to end — which
        // on this short screen was the middle, with a third of the phone
        // empty underneath it. A version number belongs at the foot of the
        // screen, which is where somebody asked for it goes looking.
        .safeAreaInset(edge: .bottom) {
            appFooter
                .padding(.bottom, 90)
        }
        }
        .background(Color(.systemGroupedBackground))
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $isShowingImpact) { ImpactView() }
        .onAppear {
            guard startOnImpact, !isShowingImpact else { return }
            isShowingImpact = true
        }
    }

    /// The one thing on this screen worth looking at, sized like it.
    private var impactCard: some View {
        NavigationLink {
            ImpactView()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.cardWiseBlue)
                    Text("Your impact")
                        .font(.subheadline.weight(.semibold))
                }
                Text(impactHeadline)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(Color.cardWiseBlue)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(impactCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your impact, \(impactHeadline). \(impactCaption)")
    }

    /// The figure, alone, big enough to be the reason you tapped.
    private var impactHeadline: String {
        guard impact.isRecording else { return "Off" }
        let summary = impact.summary
        guard summary.priced > 0 else { return summary.hasAnythingToShow ? "—" : "—" }
        return String(format: "$%.2f", summary.estimatedIncrementalValueCents / 100)
    }

    /// What the figure means. **Never "saved"** — nothing was discounted and
    /// no price changed; and it is the *incremental* number, what the
    /// recommended card earned over the next best card already in the wallet.
    private var impactCaption: String {
        guard impact.isRecording else {
            return "Not recording. Switch it on to see what these reminders have been worth."
        }
        let summary = impact.summary
        guard summary.priced > 0 else {
            return summary.hasAnythingToShow
                ? "Nothing priced yet — say what you spent and this fills in."
                : "Nothing yet. This fills in once a reminder leads somewhere."
        }
        return "Estimated extra rewards, over your next best card."
    }

    /// The app saying what it is, once, at the bottom of the only screen with
    /// room for it. Not a control — a version number is the first thing
    /// anybody is asked for when something goes wrong.
    private var appFooter: some View {
        VStack(spacing: 2) {
            Text("CardWise")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.primary)
            Text("Smart cards. Better decisions.")
                .font(.caption2)
                .foregroundStyle(Color.secondary)
            Text(versionText)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(Color.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Metric.tight)
        .accessibilityElement(children: .combine)
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String
        guard let build, build != version else { return "Version \(version)" }
        return "Version \(version) (\(build))"
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
