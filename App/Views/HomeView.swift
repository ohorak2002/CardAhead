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
    @Environment(NearbyPlacesStore.self) private var nearby

    let auth: LocationAuthorization
    /// Lets a row here move the tab bar, so "See all" goes to the real screen
    /// rather than pushing a second copy of it onto this stack.
    var goTo: (RootTabView.Tab) -> Void

    /// Optional, and asked for nowhere — set it in Settings or don't. A
    /// greeting that demands your name before it will say hello is a worse
    /// greeting than one that just says good morning.
    @AppStorage("preferredName") private var preferredName = ""

    @State private var isAddingCard = false

    private var opportunities: [Opportunity] {
        WalletInsights.opportunities(in: store.cards)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Metric.regular) {
                header
                if store.cards.isEmpty {
                    firstCardPrompt
                } else {
                    bestCardNow
                    quickLinks
                    opportunitySection
                    watchingBanner
                }
            }
            .padding(.bottom, 90)
        }
        .background(InterfacePalette.page)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isAddingCard) { AddCardView() }
    }

    // MARK: - The answer

    /// The nearest place where a card in this wallet beats the everyday one.
    ///
    /// **The nearest, not the richest.** A 5x card four miles away is not a
    /// recommendation, it is a suggestion to drive somewhere — and this screen
    /// is read standing on a pavement deciding what to pull out of a pocket.
    /// `results` is already ranked by whatever the map's sort says, which is
    /// the user's business and not this screen's, so the distance comparison
    /// happens here rather than being inherited.
    private var nearestOpportunity: MapPlaceResult? {
        nearby.results
            .filter(\.isOpportunity)
            .min { $0.distanceMeters < $1.distanceMeters }
    }

    /// Name the nearest opportunity's winner without recomputing its ranking.
    /// Reward wording uses the score's applied rate, never a catalog headline.
    @ViewBuilder
    private var bestCardNow: some View {
        VStack(alignment: .leading, spacing: Metric.snug) {
            if let result = nearestOpportunity,
               let recommendation = result.recommendation,
               let card = store.card(withID: recommendation.best.card.id) {
                Button { goTo(.map) } label: {
                    HStack(alignment: .top, spacing: Metric.snug) {
                        CategoryIcon(symbolName: "mappin.and.ellipse", tint: InterfacePalette.blue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Top nearby opportunity")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(InterfacePalette.blue)
                            Text(result.place.name)
                                .font(.headline)
                                .foregroundStyle(InterfacePalette.ink)
                            Text("Use \(card.displayName) · \(recommendation.best.card.currency.formatted(rate: recommendation.best.appliedRate)) \(recommendation.best.card.currency.unitNoun) here")
                                .font(.caption)
                                .foregroundStyle(InterfacePalette.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(result.distanceText)
                                .font(.caption2)
                                .foregroundStyle(InterfacePalette.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(InterfacePalette.blue)
                    }
                    .padding(Metric.regular)
                    .interfacePanel(tinted: true)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the nearby map")
                .padding(.horizontal, Metric.margin)
            } else {
                Button { goTo(.map) } label: { allSetPanel }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the nearby map")
                    .padding(.horizontal, Metric.margin)
            }
        }
    }

    /// The calm empty state. Three different reasons there is nothing to say,
    /// and each one says which it is — "nothing nearby pays more" and "the map
    /// has not looked yet" are very different facts about the app, and a
    /// single cheerful "You're all set" for both is the kind of empty state
    /// that reads as an apology.
    private var allSetPanel: some View {
        HStack(spacing: Metric.snug) {
            Image(systemName: allSetSymbol)
                .font(.title3)
                .foregroundStyle(Color.cardWiseActionInk)
                .frame(width: 38, height: 38)
                .background(Color.cardWiseBlue.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(allSetTitle)
                    .font(.subheadline.weight(.semibold))
                Text(allSetDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Metric.regular)
        .cardWisePanel()
        .accessibilityElement(children: .combine)
    }

    private var allSetSymbol: String {
        nearby.results.isEmpty ? "location.magnifyingglass" : "checkmark.circle"
    }

    private var allSetTitle: String {
        nearby.results.isEmpty ? "Nothing looked up yet" : "You're all set"
    }

    private var allSetDetail: String {
        nearby.results.isEmpty
            ? "Open the map and CardWise will check what is around you."
            : "None of the places shown has a bonus category for your wallet."
    }

    // MARK: - The navy top

    private var header: some View {
        VStack(alignment: .leading, spacing: Metric.roomy) {
            HStack {
                (Text("Card").foregroundColor(.white)
                 + Text("Wise").foregroundColor(InterfacePalette.cyan))
                    .font(.title3.weight(.bold))
                Spacer()
                Button { goTo(.more) } label: {
                    Image(systemName: "person.crop.circle")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: Metric.minimumTarget, height: Metric.minimumTarget)
                }
                .accessibilityLabel("Profile and settings")
            }
            VStack(alignment: .leading, spacing: Metric.tight) {
                greetingText
                    .font(.system(.title).weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("The right card. Right when you need it.")
                    .font(.footnote)
                    .foregroundStyle(Color.cardWiseLightBlue)
            }
            if !store.cards.isEmpty {
                nearbyShortcut
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

    /// "Good morning, **Oren**" — with the name picked out, the way the mockup
    /// does it.
    ///
    /// One accessible phrase, with the name on a second line in cyan against
    /// the deep navy header. No name is invented for a fresh wallet.
    private var greetingText: Text {
        let name = preferredName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            return Text(timeOfDay).foregroundColor(.white)
        }
        return Text("\(timeOfDay),\n").foregroundColor(.white)
            + Text(name).foregroundColor(InterfacePalette.cyan)
    }

    private var nearbyShortcut: some View {
        let count = nearby.results.filter(\.isOpportunity).count
        return Button { goTo(.map) } label: {
            HStack(spacing: Metric.snug) {
                Image(systemName: "mappin.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Color.cardWiseLightBlue)
                VStack(alignment: .leading, spacing: 4) {
                    Text(count > 0
                         ? "\(count) \(count == 1 ? "opportunity" : "opportunities") nearby"
                         : "Explore nearby places")
                        .font(.subheadline.weight(.semibold))
                    Text("Find the best card to use")
                        .font(.caption)
                        .foregroundStyle(Color.cardWiseLightBlue)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(.white)
            .padding(Metric.regular)
            .background {
                RoundedRectangle(cornerRadius: Metric.tileRadius)
                    .fill(LinearGradient(colors: [Color(red: 0.02, green: 0.36, blue: 0.77), .cardWiseBlue.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay {
                        RoundedRectangle(cornerRadius: Metric.tileRadius)
                            .strokeBorder(.white.opacity(0.22), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
    }

    private var quickLinks: some View {
        HStack(spacing: Metric.tight) {
            quickLink("Map", symbol: "map", tab: .map)
            quickLink("Wallet", symbol: "creditcard", tab: .wallet)
            quickLink("Benefits", symbol: "star", tab: .benefits)
            quickLink("More", symbol: "ellipsis", tab: .more)
        }
        .padding(.horizontal, Metric.margin)
    }

    private func quickLink(_ title: String, symbol: String, tab: RootTabView.Tab) -> some View {
        Button { goTo(tab) } label: {
            VStack(spacing: Metric.tight) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(.caption2.weight(.medium))
            }
            .foregroundStyle(InterfacePalette.blue)
            .frame(maxWidth: .infinity, minHeight: Metric.minimumTarget)
            .padding(.vertical, Metric.snug)
            .interfacePanel()
        }
        .buttonStyle(.plain)
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

    // MARK: - Worth doing

    @ViewBuilder
    private var opportunitySection: some View {
        VStack(alignment: .leading, spacing: Metric.snug) {
            SectionHeader("Worth doing")
                .padding(.horizontal, Metric.margin)

            if opportunities.isEmpty {
                Text("Nothing needs you right now. Every bonus you hold is switched on and nothing is about to run out.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Metric.regular)
                    .cardWisePanel()
                    .padding(.horizontal, Metric.margin)
            } else {
                VStack(spacing: Metric.snug) {
                    // Two at most. A to-do list is something people stop
                    // reading at about the third item.
                    ForEach(opportunities.prefix(2)) { opportunity in
                        NavigationLink {
                            destination(for: opportunity)
                        } label: {
                            OpportunityRow(opportunity: opportunity)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Metric.margin)
            }
        }
    }

    @ViewBuilder
    private func destination(for opportunity: Opportunity) -> some View {
        if let card = store.card(withID: opportunity.cardID) {
            CardBenefitsView(mode: .reviewing(card), presentation: .pushed)
        } else {
            WalletStackView()
        }
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
                    let width = min(geometry.size.width - Metric.loose, 280)
                    ZStack(alignment: .top) {
                        ForEach(Array(store.cards.prefix(3).enumerated().reversed()), id: \.element.id) { index, card in
                            CardFaceView(card: card, photo: store.photo(for: card))
                                .frame(width: width, height: width / 1.586)
                                .rotationEffect(.degrees(Double(index) * -4))
                                .offset(x: CGFloat(index) * -6, y: CGFloat(2 - index) * 10)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .frame(height: 200)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open your wallet, \(store.cards.count) cards")
        }
    }

    /// "Best for dining" — and true of *this* wallet, not of the card in
    /// general. See `WalletInsights.bestCategory`.
    ///
    /// Shown as the benefit *shelf* rather than the raw category, because the
    /// raw category is sometimes unreadable: Amex Gold's best rate is its 5x
    /// on hotels prepaid through Amex Travel, and "Best for travel booked
    /// through the issuer" is a label nobody would ever say out loud. "Best
    /// for travel" is the same fact in words a person uses.
    private func bestFor(_ card: Card) -> String? {
        guard let category = WalletInsights.bestCategory(for: card, in: store.cards) else { return nil }
        return "Best for \(BenefitGroup.containing(category).displayName.lowercased())"
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
}
