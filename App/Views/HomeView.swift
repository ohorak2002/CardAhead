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
            // **The order is the argument, and the first attempt had it
            // wrong.** The wallet led and the recommendation followed, which
            // reads sensibly in a list and fails on a phone: the wallet strip
            // is a third of the screen, so the one fact somebody opened the
            // app for started below the fold. The screenshot also put the same
            // Amex Gold on screen twice within an inch of itself — once in the
            // strip and once as the hero — which reads as a rendering bug
            // rather than as an answer.
            //
            // The answer leads. The wallet is still directly under it and
            // still the product; what changed is that the screen now answers
            // its own question before asking you to scroll.
            VStack(spacing: Metric.section) {
                header
                if store.cards.isEmpty {
                    firstCardPrompt
                } else {
                    bestCardNow
                    walletPeek
                    opportunitySection
                    watchingBanner
                }
            }
            .padding(.bottom, 90)
        }
        .background(Color(.systemGroupedBackground))
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

    /// The card, the reward, the reason — in that order, and nothing else.
    ///
    /// **This screen had no answer on it at all.** It carried a count of
    /// opportunities, a permissions banner and a list of chores, and the one
    /// thing a person opens this app to find out — *which card* — was never
    /// on it. The recommendation existed; it lived three taps away inside the
    /// map.
    ///
    /// Everything shown here is derived, never asserted: the place and the
    /// card come from `MapPlaceResult`, the rate from `rewardLine`, and the
    /// reason from the engine's own `best.reason` — which names the *category*
    /// ("4x at restaurants") rather than repeating the card. `headline` was
    /// tried first and read "Use Amex Gold here", directly under a line
    /// already saying "4x points with Amex Gold". When there is no fix, no
    /// lookup or no bonus anywhere nearby, this says so plainly instead of
    /// inventing something — the rule the rest of this screen already follows.
    @ViewBuilder
    private var bestCardNow: some View {
        VStack(alignment: .leading, spacing: Metric.snug) {
            SectionHeader("Use this card nearby")
                .padding(.horizontal, Metric.margin)

            if let result = nearestOpportunity,
               let recommendation = result.recommendation,
               let card = store.card(withID: recommendation.best.card.id) {
                RecommendationHero(
                    card: card,
                    photo: store.photo(for: card),
                    placeName: result.place.name,
                    distance: result.distanceText,
                    rewardLine: result.rewardLine,
                    reason: recommendation.best.reason
                ) {
                    goTo(.map)
                }
                .padding(.horizontal, Metric.margin)
            } else {
                allSetPanel
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
                .foregroundStyle(Color.cardWiseBlue)
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
            : "Nothing within reach pays more than the card you would have reached for anyway."
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

            greetingText
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            Text("The right card. Right when you need it.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))

            // **The mockup's one real piece of layering.** What is nearby sat
            // below the navy as another white card in a column of white
            // cards, which is why the header read as a coloured strip rather
            // than as a place. Inside it, on a translucent panel, it is the
            // thing the screen opens *with* — and the hero stops being three
            // lines of text with nothing in it.
            if !store.cards.isEmpty {
                nearbyBanner
                    .padding(.top, Metric.tight)
            }
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

    private var timeOfDay: String {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour < 12 ? "Good morning" : (hour < 18 ? "Good afternoon" : "Good evening")
    }

    /// "Good morning, **Oren**" — with the name picked out, the way the mockup
    /// does it.
    ///
    /// Two concatenated `Text`s rather than two views, so it stays one
    /// paragraph and wraps as one. The name's colour is Light Blue and
    /// **deliberately not the mockup's Accent Blue**, which measures 1.70:1
    /// against the lighter end of the gradient behind it — see
    /// `Color.cardWiseLightBlue`.
    private var greetingText: Text {
        let name = preferredName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            return Text(timeOfDay).foregroundColor(.white)
        }
        return Text("\(timeOfDay), ").foregroundColor(.white)
            + Text(name).foregroundColor(.cardWiseLightBlue)
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
            HeroBanner(
                symbolName: "mappin.and.ellipse",
                title: count == 1 ? "1 opportunity nearby" : "\(count) opportunities nearby",
                detail: "Places within \(nearby.filter.distance.displayName) where one of your cards pays more than usual."
            ) { goTo(.map) }
        } else if !nearby.results.isEmpty {
            HeroBanner(
                symbolName: "map",
                title: "\(nearby.results.count) places nearby",
                detail: "None of them pays more than the card you would have reached for anyway."
            ) { goTo(.map) }
        } else {
            HeroBanner(
                symbolName: "map",
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
            }
            .buttonStyle(.cardWisePrimary)
            .padding(.top, Metric.tight)
        }
        .padding(Metric.roomy)
        .cardWisePanel()
        .padding(.horizontal, Metric.margin)
    }
}

/// The status line under the header. One symbol, two lines, a chevron.
/// A `HomeBanner` that lives **inside** the navy header rather than under it.
///
/// Same row, different ground, and the difference is the whole point: on the
/// page it would be one more white card in a column of white cards, and in the
/// header it is what the header is *about*. The mockup does this once, on this
/// one banner, which is why the hero in it reads as a place and the app's read
/// as a strip of paint.
///
/// **Every colour here is white at an opacity, never a palette colour.** The
/// ground is a gradient from `#0B1F44` to `#1E56D6`, so anything drawn on it
/// has to survive both ends — and the palette's own blues do not: Accent Blue
/// measures 1.70:1 against the lighter end. White at 15% gives a panel that is
/// 10.3:1 against the navy end and 4.6:1 against the blue one, with white text
/// legible on both.
private struct HeroBanner: View {
    let symbolName: String
    let title: String
    let detail: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Metric.snug) {
                Image(systemName: symbolName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Metric.tight)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(Metric.snug)
            .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: Metric.tileRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

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
