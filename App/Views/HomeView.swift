import SwiftUI
import UIKit
import CardKit

/// The first tab: what is worth knowing right now, and a way into everything
/// else.
///
/// The hardest thing about this screen is what it must *not* claim. A home
/// screen with nothing true to say is under enormous pressure to invent
/// something, and the version of CardWise that opens on "3 opportunities
/// nearby" when it is watching nothing and knows nothing has told a small lie
/// before the user has even scrolled. So every line here is derived from
/// something real:
///
/// - the watching banner counts regions `RegionMonitor` has actually
///   registered, and turns into the permission prompt when there are none
///   because the permission is missing;
/// - opportunities come from `WalletInsights.opportunities`, which only
///   surfaces things with a genuine deadline and a genuine action;
/// - the wallet peek is the wallet.
///
/// When there is nothing to report it says so plainly. An honest quiet screen
/// is the app working.
struct HomeView: View {

    @Environment(WalletStore.self) private var store
    @Environment(RegionMonitor.self) private var monitor
    @Environment(ReminderCenter.self) private var reminders
    @Environment(OrganizationStore.self) private var organization

    let auth: LocationAuthorization
    /// Lets a row here move the tab bar, so "See all" goes to the real screen
    /// rather than pushing a second copy of it onto this stack.
    var goTo: (RootTabView.Tab) -> Void

    /// Optional, and asked for nowhere — set it in Settings or don't. A
    /// greeting that demands your name before it will say hello is a worse
    /// greeting than one that just says good morning.
    @AppStorage("preferredName") private var preferredName = ""

    @State private var isAddingCard = false

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: Metric.regular) {
                header
                if store.cards.isEmpty {
                    firstCardPrompt
                } else {
                    TodayDashboard { goTo(.map) }.id("today")
                    watchingBanner
                }
            }
            .padding(.bottom, 90)
        }
        .background(InterfacePalette.page)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isAddingCard) { AddCardView() }
        .onAppear {
            if DemoSeed.requestedTab == "today" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { proxy.scrollTo("today", anchor: .top) }
            }
        }
        }
    }

    // MARK: - The navy top

    private var header: some View {
        VStack(alignment: .leading, spacing: Metric.regular) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    (Text("Card").foregroundColor(.white)
                     + Text("Wise").foregroundColor(InterfacePalette.cyan))
                        .font(.title.weight(.bold))
                        .minimumScaleFactor(0.85)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Text("The right card. Right when you need it.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.cardWiseLightBlue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer()
                Button { goTo(.more) } label: {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: Metric.roomy))
                        .foregroundStyle(.white)
                        .frame(width: Metric.minimumTarget, height: Metric.minimumTarget)
                }
                .accessibilityLabel("Profile and settings")
            }
            greetingText
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .accessibilityElement(children: .combine)
            if !store.cards.isEmpty {
                walletPeek
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Metric.margin)
        .padding(.top, Metric.tight)
        .padding(.bottom, Metric.roomy)
        .background {
            HomeAtmosphere()
            .clipShape(UnevenRoundedRectangle(
                bottomLeadingRadius: Metric.roomy,
                bottomTrailingRadius: Metric.roomy
            ))
            .ignoresSafeArea(edges: .top)
        }
    }

    private var timeOfDay: String {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour < 12 ? "Good morning" : (hour < 18 ? "Good afternoon" : "Good evening")
    }

    /// The greeting is one calm line below the brand lockup. Keeping a name
    /// inline gives it a natural rhythm without turning it into a second title.
    private var greetingText: Text {
        let name = preferredName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            return Text(timeOfDay).foregroundColor(.white)
        }
        return Text("\(timeOfDay), ").foregroundColor(.white)
            + Text(name).foregroundColor(InterfacePalette.cyan)
    }

    // MARK: - What it is doing right now

    /// The one line that says whether the app is actually working.
    ///
    /// Everything CardWise does happens while it is closed, so without this
    /// there is no way to tell a quiet afternoon from a permission somebody
    /// declined three weeks ago.
    @ViewBuilder
    private var watchingBanner: some View {
        if !auth.hasAlways || !reminders.isAuthorized {
            HomeBanner(
                symbolName: "bell.badge",
                tint: .cardWiseWarning,
                title: "Reminders are off",
                detail: missingPermission
            ) { goTo(.more) }
        } else if monitor.monitoredCount > 0 {
            HomeBanner(
                symbolName: "location.fill",
                tint: .cardWiseBlue,
                title: "Watching \(monitor.monitoredCount) places nearby",
                detail: "You'll be told when one of your cards wins somewhere."
            ) { goTo(.more) }
        } else {
            HomeBanner(
                symbolName: "location",
                tint: .secondary,
                title: "Nothing nearby to watch",
                detail: "No shop within reach pays a bonus on your cards."
            ) { goTo(.more) }
        }
    }

    private var missingPermission: String {
        if !auth.hasAlways {
            return "CardWise needs Always location to notice you have arrived."
        }
        return "It can see where you are. It just cannot tell you about it."
    }

    // MARK: - The cards, briefly

    private var walletPeek: some View {
        VStack(alignment: .leading, spacing: Metric.snug) {
            HStack {
                Text("Your wallet").font(.headline)
                Spacer()
                Text("\(store.cards.count) \(store.cards.count == 1 ? "card" : "cards")")
                    .font(.caption)
                    .foregroundStyle(Color.cardWiseLightBlue)
            }
            .foregroundStyle(.white)

            Button { goTo(.wallet) } label: {
                GeometryReader { geometry in
                    let width = max(1, min(geometry.size.width - Metric.loose, 250))
                    ZStack(alignment: .top) {
                        ForEach(Array(organization.visibleCards(in: store.cards).prefix(3).enumerated().reversed()), id: \.element.id) { index, card in
                            CardFaceView(card: card, photo: store.photo(for: card))
                                .frame(width: width, height: width / 1.586)
                                .rotationEffect(.degrees(Double(index) * -4))
                                .offset(x: CGFloat(index) * -6, y: CGFloat(2 - index) * 10)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .frame(height: organization.visibleCards(in: store.cards).isEmpty ? Metric.minimumTarget : 180)
                .overlay {
                    if organization.visibleCards(in: store.cards).isEmpty {
                        Label("Your cards are hidden. Open wallet to manage.", systemImage: "eye.slash")
                            .font(.caption).foregroundStyle(.white)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open your wallet, \(store.cards.count) cards")
        }
    }

    // MARK: - Nothing yet

    private var firstCardPrompt: some View {
        VStack(spacing: Metric.regular) {
            Image(systemName: "creditcard.fill")
                .font(.system(size: 42))
                .foregroundStyle(Color.cardWiseActionInk)
            Text("Add your first card")
                .font(.title3.weight(.semibold))
            Text("Tell CardWise which cards you carry, once. It works out the rest — and tells you which one to reach for when you get somewhere.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                isAddingCard = true
            } label: {
                Text("Add a card")
            }
            .buttonStyle(.cardWisePrimary)
            .padding(.top, Metric.tight)
        }
        .padding(Metric.roomy)
        .cardWisePanel()
        .padding(.horizontal, Metric.margin)
    }
}

private struct HomeBanner: View {
    let symbolName: String
    let tint: Color
    let title: String
    let detail: String
    var action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var layout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Metric.snug))
            : AnyLayout(HStackLayout(spacing: Metric.snug))
    }

    var body: some View {
        Button(action: action) {
            layout {
                CategoryIcon(symbolName: symbolName, tint: tint, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: Metric.tight) }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(Metric.regular)
            .cardWisePanel()
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Metric.margin)
        .accessibilityElement(children: .combine)
    }
}

/// One thing worth doing, with the clock on it.
private struct OpportunityRow: View {
    let opportunity: Opportunity

    @Environment(\.dynamicTypeSize) private var typeSize

    private var layout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Metric.snug))
            : AnyLayout(HStackLayout(spacing: Metric.snug))
    }

    var body: some View {
        layout {
            CategoryIcon(
                symbolName: opportunity.category?.symbolName ?? "gift.fill",
                tint: opportunity.category?.tint ?? Color.cardWiseWarning,
                size: 42
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(opportunity.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(opportunity.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: Metric.tight) }
            if let days = daysLeft {
                TagPill(text: days, tint: .cardWiseWarning)
            }
        }
        .padding(Metric.regular)
        .cardWisePanel()
        .accessibilityElement(children: .combine)
    }

    /// Only when it is close enough to matter. "Expires in 340 days" is not
    /// urgency, it is noise wearing urgency's clothes.
    private var daysLeft: String? {
        guard let deadline = opportunity.deadline else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: deadline).day ?? 0
        guard days >= 0, days <= 45 else { return nil }
        return days == 0 ? "Today" : "\(days)d left"
    }
}

#Preview {
    NavigationStack {
        HomeView(auth: LocationAuthorization()) { _ in }
    }
    .environment(WalletStore.previewStore())
    .environment(RegionMonitor())
    .environment(ReminderCenter())
    .environment(ImpactStore.previewStore())
    .environment(NearbyPlacesStore())
    .environment(OrganizationStore(fileURL: .temporaryDirectory.appendingPathComponent("preview-organization.json")))
}
