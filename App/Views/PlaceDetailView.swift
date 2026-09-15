import SwiftUI
import UIKit
import CardKit

/// One place, opened: what it is, how to get to it, and which card to hand
/// over when you are standing in it.
///
/// **The last section is why this screen exists.** Everything above it —
/// address, hours, phone — any map app already does better. What no map app
/// can do is rank *your* wallet against this till, and that is the part built
/// from the same `RecommendationEngine` that writes the lock-screen reminder.
/// It is the same answer, arrived at the same way; the only difference is that
/// here you asked for it.
///
/// **It opens on a photograph of the place, where there is one.** An earlier
/// note here argued the opposite — that a picture of a shop front tells
/// somebody deciding which card to pull out nothing, and the navy header said
/// "you are somewhere new" for free. The first half is true and the wrong
/// test: this screen is reached by tapping one row out of twenty, and the
/// first thing it has to establish is *that the right row was tapped*. A
/// photograph does that in a glance and a name in a navy bar does not.
///
/// The navy header has not been deleted, because most places have no
/// photograph and a screen with a grey rectangle where the picture should be
/// is worse than one that never promised a picture. When there is no photo
/// handle, the header this app wears everywhere else is what you get.
struct PlaceDetailView: View {

    @Environment(NearbyPlacesStore.self) private var places
    @Environment(WalletStore.self) private var wallet
    @Environment(RegionMonitor.self) private var monitor
    @Environment(NotificationPolicyStore.self) private var notifications
    @Environment(ImpactStore.self) private var impact
    @Environment(\.openURL) private var openURL

    /// The row the list already had. Replaced by a richer copy once the
    /// details lookup answers — and the screen is complete without it, which
    /// is what happens offline and on a key with no details quota.
    @State private var place: MapPlace
    @State private var isLoadingDetails = false

    init(place: MapPlace) {
        _place = State(initialValue: place)
    }

    /// Whether this exact shop is one of the twenty currently geofenced.
    ///
    /// The join is the place provider's own id, kept by both halves of the
    /// app — see `RegionPlan.watchedPlaceIDs`.
    private var isWatched: Bool {
        monitor.plan?.watchedPlaceIDs.contains(place.id) ?? false
    }

    private var recommendation: Recommendation? {
        guard !wallet.cards.isEmpty, let context = place.purchaseContext() else { return nil }
        return RecommendationEngine().recommend(from: wallet.cards, in: context)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metric.roomy) {
                header
                actions
                recommendationSection
                factsSection
                nearbyCards
                muteSection
            }
            .padding(.bottom, 90)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(place.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !isLoadingDetails else { return }
            isLoadingDetails = true
            place = await places.loadDetails(for: place)
            isLoadingDetails = false
        }
    }

    // MARK: - The top

    /// A photograph when the place has one, the navy header when it does not.
    @ViewBuilder
    private var header: some View {
        if place.photo != nil {
            VStack(alignment: .leading, spacing: Metric.snug) {
                photoHeader
                // The rating, whether it is open and today's hours. On the
                // navy header these are white on navy; here they are ordinary
                // text on the page, because stacking four more pieces of
                // white type over a photograph is where this stops being a
                // photograph and starts being a poster.
                factsStrip
                    .padding(.horizontal, Metric.margin)
            }
        } else {
            navyHeader
        }
    }

    /// Rating, open state and today's hours, in whatever combination the
    /// provider actually supplied. Each part is dropped when it is unknown
    /// rather than drawn empty.
    @ViewBuilder
    private var factsStrip: some View {
        HStack(spacing: Metric.snug) {
            if let rating = place.rating {
                Label {
                    Text(String(format: "%.1f", rating)).monospacedDigit()
                        + Text(place.ratingCount.map { " (\($0.formatted()))" } ?? "")
                } icon: {
                    Image(systemName: "star.fill")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            if let open = place.isOpenNow {
                Text(open ? "Open" : "Closed")
                    .font(.footnote.weight(.semibold))
                    // Explicit `Color` on both branches — see the ternary
                    // trap in CLAUDE.md.
                    .foregroundStyle(open ? Color.cardWiseSuccess : Color.secondary)
            }
            if let hours = place.hoursToday {
                Text(hours)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    /// The place, full width, with its name written across the bottom of it.
    ///
    /// **The scrim is not decoration and its numbers are not taste.** White
    /// text over an arbitrary photograph is unreadable about a third of the
    /// time — a bright sky, a white tablecloth, a snow-covered car park — and
    /// no amount of shadow fixes it reliably. A gradient that reaches 78%
    /// black at the bottom edge makes the band the text sits in dark whatever
    /// is behind it, including the coloured fallback tile drawn while the
    /// image is still arriving.
    private var photoHeader: some View {
        PlacePhotoView(place: place, use: .hero, cornerRadius: 0)
            .frame(height: 260)
            .frame(maxWidth: .infinity)
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.12), location: 0.45),
                        .init(color: .black.opacity(0.78), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(place.name)
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Text(place.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
                .padding(.horizontal, Metric.margin)
                .padding(.bottom, Metric.regular)
            }
            // **Deliberately not `ignoresSafeArea`.** This screen is pushed,
            // so it has a navigation bar with a back button and an inline
            // title in it. A photograph run up under that bar puts the place's
            // name in small black type on the picture, eight points above the
            // same name in large white type — and on a light photograph the
            // back chevron disappears entirely.
            .overlay(alignment: .bottomTrailing) {
                // The credit Google's terms require, on the one screen with
                // room to read one. Quiet, and over the darkest part of the
                // scrim so it is legible without being loud.
                PlacePhotoCredit(photo: place.photo)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, Metric.margin)
                    .padding(.bottom, 4)
            }
    }

    private var navyHeader: some View {
        VStack(alignment: .leading, spacing: Metric.snug) {
            HStack(spacing: Metric.snug) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(0.18))
                    .frame(width: 52, height: 52)
                    .overlay {
                        Image(systemName: place.mapCategory.symbolName)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(place.name)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Text(place.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: Metric.snug) {
                if let rating = place.rating {
                    Label {
                        Text(String(format: "%.1f", rating)).monospacedDigit()
                            + Text(place.ratingCount.map { " (\($0.formatted()))" } ?? "")
                    } icon: {
                        Image(systemName: "star.fill")
                    }
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.9))
                }
                if let open = place.isOpenNow {
                    Text(open ? "Open" : "Closed")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, Metric.tight)
                        .padding(.vertical, 3)
                        .background(
                            open ? Color.cardWiseSuccess.opacity(0.35) : Color.white.opacity(0.18),
                            in: Capsule()
                        )
                }
                if let hours = place.hoursToday {
                    Text(hours)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Metric.margin)
        .padding(.top, Metric.regular)
        .padding(.bottom, Metric.roomy)
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

    // MARK: - Getting there and getting hold of them

    /// Four buttons, and a button that cannot do anything is not shown rather
    /// than shown greyed out — a disabled control asks the user to work out
    /// why, which on this screen is always "the place provider did not say".
    private var actions: some View {
        HStack(spacing: Metric.snug) {
            if let phone = place.phone, let url = telephoneURL(for: phone) {
                ActionButton(symbolName: "phone.fill", title: "Call") { openURL(url) }
            }
            ActionButton(symbolName: "location.fill", title: "Directions") { openDirections() }
            if let website = place.website, let url = URL(string: website) {
                ActionButton(symbolName: "safari.fill", title: "Website") { openURL(url) }
            }
            ShareLink(item: shareURL) {
                ActionLabel(symbolName: "square.and.arrow.up", title: "Share")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Metric.margin)
    }

    // MARK: - Quiet, here

    /// The one place a person can actually silence a shop.
    ///
    /// **`NotificationPolicy` could hold a mute from the day it was written,
    /// and nothing could set one.** A policy that supports a thing no screen
    /// offers is a promise, not a feature — and the obvious home for it is not
    /// a settings list, where somebody would have to already know the shop's
    /// name to go and find it. It is here, on the shop, at the moment they are
    /// thinking about it.
    ///
    /// Shown only for a place the app is actually watching. Offering to
    /// silence somewhere that was never going to say anything is an option
    /// that does nothing, which is worse than no option at all.
    @ViewBuilder
    private var muteSection: some View {
        if isWatched || isMuted {
            VStack(alignment: .leading, spacing: Metric.snug) {
                SectionHeader("Reminders here")
                if isMuted {
                    HStack(alignment: .firstTextBaseline, spacing: Metric.snug) {
                        Label("Muted", systemImage: "bell.slash.fill")
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                        Spacer(minLength: 0)
                        Button("Unmute") { notifications.unmute(merchantID: place.id) }
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(Metric.regular)
                    .cardWisePanel()
                } else {
                    Menu {
                        ForEach(NotificationPolicy.MuteDuration.allCases, id: \.self) { duration in
                            Button(duration.displayName) { mute(for: duration) }
                        }
                    } label: {
                        HStack(spacing: Metric.snug) {
                            Image(systemName: "bell.slash")
                            Text("Mute reminders here")
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                                .foregroundStyle(Color.secondary)
                        }
                        .font(.subheadline)
                        .padding(Metric.regular)
                        .cardWisePanel()
                    }
                }
                Text(muteFooter)
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Metric.margin)
        }
    }

    private var isMuted: Bool {
        notifications.policy.isMuted(merchantID: place.id, at: Date())
    }

    /// **Muting stops the words, not the watching.** The geofence stays
    /// registered and the arrival still reaches the impact ledger, so "how
    /// often was I somewhere a card would have helped" keeps its answer. What
    /// changes is that nothing is said.
    private var muteFooter: String {
        isMuted
            ? "CardWise still notices when you are here. It just says nothing."
            : "Stops reminders about this place. It keeps watching, and keeps counting."
    }

    private func mute(for duration: NotificationPolicy.MuteDuration) {
        notifications.mute(merchantID: place.id, for: duration)
        impact.recordSilenced(category: place.spendingCategory)
    }

    /// Apple Maps rather than a coordinate URL of our own: the phone knows
    /// which navigation app the user prefers and this is the handoff it
    /// understands.
    private func openDirections() {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "daddr", value: "\(place.coordinate.latitude),\(place.coordinate.longitude)"),
            URLQueryItem(name: "q", value: place.name),
            URLQueryItem(name: "dirflg", value: "d")
        ]
        guard let url = components?.url else { return }
        openURL(url)
    }

    private var shareURL: URL {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "ll", value: "\(place.coordinate.latitude),\(place.coordinate.longitude)"),
            URLQueryItem(name: "q", value: place.name)
        ]
        return components?.url ?? URL(string: "https://maps.apple.com/")!
    }

    private func telephoneURL(for phone: String) -> URL? {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel://\(digits)")
    }

    // MARK: - Which card

    @ViewBuilder
    private var recommendationSection: some View {
        VStack(alignment: .leading, spacing: Metric.snug) {
            SectionHeader("Which card to use here")
                .padding(.horizontal, Metric.margin)

            if let recommendation {
                VStack(alignment: .leading, spacing: Metric.snug) {
                    HStack(spacing: Metric.snug) {
                        CardThumbnail(
                            card: recommendation.best.card,
                            photo: wallet.photo(for: recommendation.best.card)
                        )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(recommendation.best.card.displayName)
                                .font(.subheadline.weight(.semibold))
                            Text(recommendation.best.reason)
                                .font(.caption)
                                .foregroundStyle(Color.cardWiseBlue)
                        }
                        Spacer(minLength: 0)
                    }
                    // **This was `recommendation.detail`, and it said the same
                    // thing twice.** `detail` is `"\(best.reason) at
                    // \(merchant)"` — so the screen read "2% on everything"
                    // in blue and then "2% on everything at Piedmont House
                    // Hotel" in grey twenty points underneath, on a screen
                    // whose title is already the name of the place.
                    //
                    // What belongs in that slot is the *why*: the comparison
                    // the ranking just made and discarded. See
                    // `Recommendation.runnerUpLine`, which is the same
                    // sentence the map's place card and Home's hero use, and
                    // which is nil rather than filler when there is nothing
                    // to compare against.
                    if let why = recommendation.runnerUpLine {
                        Text(why)
                            .font(.footnote)
                            .foregroundStyle(Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let nudge = recommendation.activationNudge {
                        Label(nudge.sentence, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(Color.cardWiseWarning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(recommendation.caveats, id: \.self) { caveat in
                        Label(caveat, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if isWatched {
                        // Spelled out rather than shown as the bell the map
                        // and the list use, because this is the one screen
                        // where somebody has time to read a sentence — and
                        // a reminder arriving out of nowhere is the part of
                        // this app that feels like magic.
                        Label(
                            "CardWise is watching this place, so you will be reminded when you arrive without opening the app.",
                            systemImage: "bell.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(Color.cardWiseBlue)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    if place.confidence == .categoryOnly {
                        Label(
                            "This is one set of coordinates with a lot of tills behind it, so this is the answer for \(place.mapCategory.displayName.lowercased()) rather than for one shop.",
                            systemImage: "questionmark.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Metric.regular)
                .cardWisePanel()
                .padding(.horizontal, Metric.margin)
            } else {
                Text(noRecommendationReason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Metric.regular)
                    .cardWisePanel()
                    .padding(.horizontal, Metric.margin)
            }
        }
    }

    /// Two silences with two causes, and neither of them is "we do not know".
    private var noRecommendationReason: String {
        if wallet.cards.isEmpty {
            return "There are no cards in your wallet yet, so there is nothing to rank. Add one and this fills in."
        }
        return "CardWise cannot tell what this sort of place codes as, so it will not guess a category. Whichever card you would normally use is as good an answer as it has."
    }

    // MARK: - What the provider said

    @ViewBuilder
    private var factsSection: some View {
        if place.address != nil || place.hoursToday != nil || place.phone != nil {
            VStack(alignment: .leading, spacing: Metric.snug) {
                SectionHeader("Details")
                    .padding(.horizontal, Metric.margin)

                VStack(alignment: .leading, spacing: Metric.snug) {
                    if let address = place.address {
                        Fact(symbolName: "mappin.circle", text: address)
                    }
                    if let hours = place.hoursToday {
                        Fact(symbolName: "clock", text: "Today: \(hours)")
                    }
                    if let phone = place.phone {
                        Fact(symbolName: "phone", text: phone)
                    }
                }
                .padding(Metric.regular)
                .cardWisePanel()
                .padding(.horizontal, Metric.margin)
            }
        }
    }

    // MARK: - The rest of the wallet

    /// Every other card, and what each would earn here.
    ///
    /// Straight off `recommendation.alternates`, which is the same ranking the
    /// winner came out of — **not** a second pass with its own rules. A
    /// parallel ranking path in a browsing screen is exactly how a UI starts
    /// disagreeing with the notification.
    @ViewBuilder
    private var nearbyCards: some View {
        if let alternates = recommendation?.alternates, !alternates.isEmpty {
            VStack(alignment: .leading, spacing: Metric.snug) {
                SectionHeader("Your other cards here")
                    .padding(.horizontal, Metric.margin)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Metric.snug) {
                        ForEach(alternates) { score in
                            VStack(alignment: .leading, spacing: Metric.tight) {
                                CardThumbnail(card: score.card, photo: wallet.photo(for: score.card))
                                Text(score.card.displayName)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Text(score.reason)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 140, alignment: .leading)
                            .padding(Metric.snug)
                            .cardWisePanel(radius: Metric.tileRadius)
                        }
                    }
                    .padding(.horizontal, Metric.margin)
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

// MARK: - Pieces

private struct Fact: View {
    let symbolName: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Metric.snug) {
            Image(systemName: symbolName)
                .font(.subheadline)
                .foregroundStyle(Color.cardWiseBlue)
                .frame(width: 22)
            Text(text)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The look of one of the four round actions across the top.
private struct ActionLabel: View {
    let symbolName: String
    let title: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbolName)
                .font(.headline)
                .foregroundStyle(Color.cardWiseBlue)
                .frame(width: 46, height: 46)
                .background(.background, in: Circle())
                .shadow(color: Color.cardWiseNavy.opacity(0.08), radius: 6, y: 2)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ActionButton: View {
    let symbolName: String
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ActionLabel(symbolName: symbolName, title: title)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

#Preview {
    NavigationStack {
        PlaceDetailView(place: MapPlace(
            id: "preview",
            name: "The Capital Grille",
            coordinate: GeoCoordinate(latitude: 33.8484, longitude: -84.3627),
            placeTypes: ["steak_house", "restaurant"],
            typeDescription: "Steakhouse",
            rating: 4.6,
            ratingCount: 1234,
            address: "255 E Paces Ferry Rd NE, Atlanta, GA",
            isOpenNow: true,
            hoursToday: "11:00 AM – 10:00 PM",
            phone: "(404) 262-1162",
            website: "https://www.thecapitalgrille.com/"
        ))
    }
    .environment(WalletStore.previewStore())
    .environment(NearbyPlacesStore())
    .environment(RegionMonitor())
}
