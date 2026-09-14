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
            VStack(spacing: Metric.roomy) {
                header
                if store.cards.isEmpty {
                    firstCardPrompt
                } else {
                    nearbyBanner
                    watchingBanner
                    opportunitySection
                    walletPeek
                }
            }
            .padding(.bottom, 90)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isAddingCard) { AddCardView() }
    }

    // MARK: - The navy top

    private var header: some View {
        VStack(alignment: .leading, spacing: Metric.tight) {
            HStack {
                Text("CardWise")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
            }
            .padding(.top, Metric.tight)

            Text(greeting)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            Text("The right card. Right when you need it.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Metric.margin)
        .padding(.top, Metric.roomy)
        .padding(.bottom, Metric.roomy)
        // **The gradient reaches under the status bar; the text does not.**
        // `ignoresSafeArea` applied to the header itself moves the whole
        // thing up, and the title lands on top of the clock. Applied to the
        // background shape alone, only the paint extends.
        .background {
            UnevenRoundedRectangle(
                bottomLeadingRadius: 28,
                bottomTrailingRadius: 28,
                style: .continuous
            )
            .fill(.cardWiseHeader)
            .ignoresSafeArea(edges: .top)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let time = hour < 12 ? "Good morning" : (hour < 18 ? "Good afternoon" : "Good evening")
        let name = preferredName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? time : "\(time), \(name)"
    }

    // MARK: - What is around you

    /// The one line the mockup opens on: "You have 3 opportunities nearby."
    ///
    /// **It says a number only when it has counted one.** The map is the only
    /// thing in the app that knows what is nearby, and it knows nothing until
    /// somebody has opened it and it has had a fix and a lookup — so most of
    /// the time on a fresh launch this is an invitation to look rather than a
    /// count, and it says so. An opening screen that greets everybody with
    /// "3 opportunities nearby" before it has looked anywhere is the exact lie
    /// this screen's doc comment exists to prevent.
    ///
    /// "Opportunity" means something precise here and is counted in one place,
    /// `MapPlaceResult.isOpportunity`: a nearby place where a card in this
    /// wallet pays **more than its everyday rate**. A wallet of flat-rate
    /// cards produces zero of them however busy the high street is, which is
    /// the correct answer rather than a bug.
    @ViewBuilder
    private var nearbyBanner: some View {
        let count = nearby.opportunityCount
        if count > 0 {
            HomeBanner(
                symbolName: "mappin.and.ellipse",
                tint: .cardWiseBlue,
                title: count == 1 ? "1 opportunity nearby" : "\(count) opportunities nearby",
                detail: "Places within \(nearby.filter.distance.displayName) where one of your cards pays more than usual."
            ) { goTo(.map) }
        } else if !nearby.results.isEmpty {
            HomeBanner(
                symbolName: "map",
                tint: .secondary,
                title: "\(nearby.results.count) places nearby",
                detail: "None of them pays more than the card you would have reached for anyway."
            ) { goTo(.map) }
        } else {
            HomeBanner(
                symbolName: "map",
                tint: .cardWiseBlue,
                title: "See what is around you",
                detail: "The map shows nearby shops and which of your cards wins at each."
            ) { goTo(.map) }
        }
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
            SectionHeader(title: "Your wallet") {
                Button("See all") { goTo(.wallet) }
            }
            .padding(.horizontal, Metric.margin)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Metric.regular) {
                    ForEach(store.cards) { card in
                        Button {
                            goTo(.wallet)
                        } label: {
                            CardFaceView(
                                card: card,
                                highlight: bestFor(card),
                                photo: store.photo(for: card)
                            )
                            .frame(width: 260)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Metric.margin)
                .padding(.vertical, Metric.tight)
            }
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
                .foregroundStyle(Color.cardWiseBlue)
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
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Metric.snug)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, Metric.tight)
        }
        .padding(Metric.roomy)
        .cardWisePanel()
        .padding(.horizontal, Metric.margin)
    }
}

/// The status line under the header. One symbol, two lines, a chevron.
private struct HomeBanner: View {
    let symbolName: String
    let tint: Color
    let title: String
    let detail: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Metric.snug) {
                CategoryIcon(symbolName: symbolName, tint: tint, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: Metric.tight)
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

    var body: some View {
        HStack(spacing: Metric.snug) {
            CategoryIcon(
                symbolName: opportunity.category?.symbolName ?? "gift.fill",
                tint: opportunity.category?.tint ?? Color.cardWiseWarning,
                size: 42
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(opportunity.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(opportunity.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Metric.tight)
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
