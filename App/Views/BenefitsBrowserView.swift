import SwiftUI
import UIKit
import CardKit

/// Benefits across the whole wallet, not down one card.
///
/// The question people actually have is "what am I carrying for dining", not
/// "what does my Gold do" — and answering the second when they asked the first
/// is why benefits usually end up buried in a card editor nobody opens. So the
/// shelf is the subject here and the card is a detail on the row.
///
/// Everything is derived by `WalletInsights` from the same `Card` the ranking
/// engine reads. There is no second list, which is the whole reason this
/// screen cannot drift out of step with what CardWise actually recommends.
struct BenefitsBrowserView: View {

    @Environment(WalletStore.self) private var store
    /// Read so the grid can drop to one column when the text stops fitting in
    /// two. See `columns`.
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var filter: Filter = .all
    @State private var openGroup: BenefitGroup?

    enum Filter: String, CaseIterable, Identifiable {
        case all, active, expiring
        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .all: return "All"
            case .active: return "Active"
            case .expiring: return "Expiring"
            }
        }
    }

    private var groups: [BenefitGroupSummary] {
        WalletInsights.benefitGroups(in: store.cards)
    }

    private var expiring: [WalletBenefit] {
        WalletInsights.expiringSoon(in: store.cards)
    }

    /// Built once per render rather than per tile: `expiringSoon` walks every
    /// benefit of every card, and seven tiles asking it the same question is
    /// seven times the work for one answer.
    private var expiringIDs: Set<String> {
        Set(expiring.map(\.id))
    }

    private var visibleGroups: [BenefitGroupSummary] {
        switch filter {
        case .all: return groups
        case .active: return groups.filter { $0.activeCount > 0 }
        case .expiring:
            let ids = Set(expiring.map(\.benefit.group))
            return groups.filter { ids.contains($0.group) }
        }
    }

    /// Two tiles across, and **one** once the text stops fitting in two.
    ///
    /// At the accessibility text sizes a half-width tile is about 175 points
    /// wide, which is not enough for the word "Groceries" — the first
    /// screenshot at the largest size rendered it as "Groce…". A two-column
    /// grid is a layout choice that assumes a text size; when the assumption
    /// stops holding, the grid has to give, not the words.
    private var columns: [GridItem] {
        guard typeSize.isAccessibilitySize else {
            return [
                GridItem(.flexible(), spacing: Metric.snug),
                GridItem(.flexible(), spacing: Metric.snug)
            ]
        }
        return [GridItem(.flexible())]
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader("Benefits", subtitle: headerSubtitle)
            Group {
                if store.cards.isEmpty {
                    emptyState
                } else {
                    content
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $openGroup) { group in
            BenefitGroupDetailView(
                group: group,
                benefits: groups.first { $0.group == group }?.benefits ?? []
            )
        }
    }

    private var headerSubtitle: String? {
        guard !store.cards.isEmpty else { return nil }
        let active = WalletInsights.activeBenefitCount(in: store.cards)
        return active == 1 ? "1 paying right now" : "\(active) paying right now"
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metric.roomy) {
                // **Chips, not a segmented control.** The map filters with
                // `CardWiseChip` and this screen filtered with a
                // `.segmented` Picker — two filter languages in one app, for
                // no reason anybody chose. The chip is the one that survived
                // because it scales to more than three options and it is the
                // control the rest of the app now speaks.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Metric.tight) {
                        ForEach(Filter.allCases) { option in
                            CardWiseChip(
                                title: option.displayName,
                                isOn: filter == option,
                                tint: .cardWiseBlue
                            ) {
                                filter = option
                            }
                        }
                    }
                    .padding(.horizontal, Metric.margin)
                    .padding(.vertical, 2)
                }
                .padding(.top, Metric.tight)

                if visibleGroups.isEmpty {
                    Text(filter == .expiring
                         ? "Nothing is about to run out."
                         : "Nothing is paying right now.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Metric.margin)
                } else {
                    LazyVGrid(columns: columns, spacing: Metric.snug) {
                        ForEach(visibleGroups) { summary in
                            Button {
                                openGroup = summary.group
                            } label: {
                                BenefitGroupTile(
                                    summary: summary,
                                    wallet: store.cards,
                                    lead: summary.lead(expiring: expiringIDs)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Metric.margin)
                }

                if !expiring.isEmpty {
                    expiringSection
                }
            }
            .padding(.bottom, 90)
        }
    }

    // MARK: - What runs out soon

    /// Only ever holds things with a real end date on them — a signup bonus
    /// deadline, a rotating quarter. See `WalletInsights.expiringSoon` for why
    /// an annual travel credit is deliberately absent rather than guessed at.
    private var expiringSection: some View {
        VStack(alignment: .leading, spacing: Metric.snug) {
            SectionHeader("Running out")
                .padding(.horizontal, Metric.margin)

            VStack(spacing: Metric.snug) {
                ForEach(expiring) { entry in
                    HStack(spacing: Metric.snug) {
                        CategoryIcon(
                            symbolName: entry.benefit.group.symbolName,
                            tint: Color.cardWiseWarning,
                            size: 40
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.benefit.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                            Text(entry.cardName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: Metric.tight)
                        if let days = daysLeft(entry) {
                            TagPill(text: days, tint: .cardWiseWarning)
                        }
                    }
                    .padding(Metric.regular)
                    .cardWisePanel()
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, Metric.margin)
        }
    }

    private func daysLeft(_ entry: WalletBenefit) -> String? {
        guard let expires = entry.benefit.expiresOn else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: expires).day ?? 0
        guard days >= 0 else { return nil }
        return days == 0 ? "Today" : "\(days)d left"
    }

    private var emptyState: some View {
        VStack(spacing: Metric.snug) {
            Image(systemName: "star")
                .font(.system(size: 38))
                .foregroundStyle(.tertiary)
            Text("No cards yet")
                .font(.title3.weight(.semibold))
            Text("Add a card and everything it is good for shows up here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(Metric.loose)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One shelf, as a tile: the symbol, the name, and the one line about it worth
/// reading.
///
/// **The third line used to be a count and the badge used to be missing.**
/// "2 paying now" is arithmetic, not information — it tells you the shelf is
/// not empty, which the tile being on screen already told you. And the "up to
/// 4x" badge appeared on two tiles out of seven, because five of them mix a
/// points card with a cash back card and `bestRateText` correctly refuses to
/// compare 4x with 3%. Five blank corners read as a rendering fault rather
/// than as restraint.
///
/// So the number is still only drawn when it is honest, and the line under the
/// name is now `BenefitGroupSummary.lead` — which always has something true to
/// say, and says the most urgent of it first: what is about to lapse, then
/// what needs switching on, then which card this shelf is really for.
private struct BenefitGroupTile: View {
    let summary: BenefitGroupSummary
    /// Needed to know what units the cards on this shelf state their rates in.
    /// See `BenefitGroupSummary.bestRateText`.
    let wallet: [Card]
    let lead: BenefitGroupSummary.Lead

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // **The rate moves under the icon rather than beside it once the
            // text is large.** Sharing a row with a 38-point square leaves
            // "4x" about 100 points, which at the accessibility sizes it
            // spends breaking itself into pieces — the loudest thing on the
            // tile, taller than the shelf it is describing.
            if typeSize.isAccessibilitySize {
                CategoryIcon(
                    symbolName: summary.group.symbolName,
                    tint: summary.group.tint,
                    size: 38
                )
                rateText
            } else {
                HStack(alignment: .firstTextBaseline) {
                    CategoryIcon(
                        symbolName: summary.group.symbolName,
                        tint: summary.group.tint,
                        size: 38
                    )
                    Spacer(minLength: 0)
                    rateText
                }
            }

            // **A fixed gap, not a `Spacer`.** The grid gives every tile in
            // a row the height of the tallest, and a `Spacer` in a stretched
            // tile pushes its name and lead to the bottom — so "Dining" sat
            // sixty points below "Groceries" in the same row, with nothing in
            // between. The panel still fills the row; its contents stay put
            // at the top where the eye expects them.
            Color.clear.frame(height: Metric.snug)

            // **No `lineLimit`.** This was `lineLimit(1)` with a 0.8 scale
            // floor, which is a quiet instruction to throw the word away when
            // it stops fitting: at the largest text size "Groceries" rendered
            // as "Groce…". A category name is the one string on this tile that
            // cannot be guessed from the rest of it.
            Text(summary.group.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(lead.text)
                .font(.caption)
                // **Two lines, reserved whether or not they are used.** The
                // grid gives a row the height of its tallest tile, so
                // "Best with Chase Freedom Flex" wrapping to two lines left
                // the tile beside it with ninety points of slack underneath.
                // Reserving the space everywhere costs one line on the short
                // tiles and makes every row the same height.
                .lineLimit(2, reservesSpace: !typeSize.isAccessibilitySize)
                // Colour is never the only signal — "Ends soon" and "Needs
                // switching on" say so in words for anybody who cannot tell
                // the amber from the grey.
                .foregroundStyle(lead.needsAttention ? Color.cardWiseWarning : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        // **`maxHeight` as well as `maxWidth`.** A `LazyVGrid` gives each item
        // its own height and centres the short one, so the moment two tiles in
        // a row disagree they float at different heights against each other.
        // Filling the row's height makes a row read as a row.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Metric.regular)
        .cardWisePanel(radius: Metric.tileRadius)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(summary.group.displayName). \(lead.text)")
    }

    @ViewBuilder
    private var rateText: some View {
        if let rate = summary.bestRateText(in: wallet) {
            Text(rate)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(summary.group.tint)
                .monospacedDigit()
        }
    }
}

/// Everything on one shelf, by card.
private struct BenefitGroupDetailView: View {
    let group: BenefitGroup
    let benefits: [WalletBenefit]

    var body: some View {
        List {
            ForEach(benefits) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(entry.benefit.title)
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: Metric.tight)
                        if !entry.benefit.isActive {
                            Text("not paying")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.cardWiseWarning)
                        }
                    }
                    Text(entry.cardName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let detail = entry.benefit.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle(group.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        BenefitsBrowserView()
    }
    .environment(WalletStore.previewStore())
}
