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

    private var visibleGroups: [BenefitGroupSummary] {
        switch filter {
        case .all: return groups
        case .active: return groups.filter { $0.activeCount > 0 }
        case .expiring:
            let ids = Set(expiring.map(\.benefit.group))
            return groups.filter { ids.contains($0.group) }
        }
    }

    private let columns = [
        GridItem(.flexible(), spacing: Metric.snug),
        GridItem(.flexible(), spacing: Metric.snug)
    ]

    var body: some View {
        Group {
            if store.cards.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Benefits")
        .navigationDestination(item: $openGroup) { group in
            BenefitGroupDetailView(
                group: group,
                benefits: groups.first { $0.group == group }?.benefits ?? []
            )
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metric.roomy) {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Metric.margin)
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
                                BenefitGroupTile(summary: summary, wallet: store.cards)
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

/// One shelf, as a tile: the symbol, the name, and how much of it is actually
/// paying right now.
private struct BenefitGroupTile: View {
    let summary: BenefitGroupSummary
    /// Needed to know what units the cards on this shelf state their rates in.
    /// See `BenefitGroupSummary.bestRateText`.
    let wallet: [Card]

    var body: some View {
        VStack(alignment: .leading, spacing: Metric.tight) {
            HStack(alignment: .top) {
                CategoryIcon(
                    symbolName: summary.group.symbolName,
                    tint: summary.group.tint,
                    size: 38
                )
                Spacer(minLength: 0)
                if let rate = summary.bestRateText(in: wallet) {
                    Text("up to \(rate)")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(summary.group.tint)
                        .monospacedDigit()
                }
            }
            Text(summary.group.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(countText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metric.regular)
        .cardWisePanel(radius: Metric.tileRadius)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(summary.group.displayName), \(countText)")
    }

    private var countText: String {
        let active = summary.activeCount
        if active == 0 { return "None paying now" }
        return active == 1 ? "1 paying now" : "\(active) paying now"
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
