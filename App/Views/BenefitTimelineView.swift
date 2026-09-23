import SwiftUI
import CardKit

struct BenefitTimelineView: View {
    @Environment(WalletStore.self) private var wallet
    @Environment(OrganizationStore.self) private var organization
    @State private var isAddingCard = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { clock in
            let deadlines = EverydayInsights.deadlines(in: wallet.cards, asOf: clock.date)
            ScrollView {
                VStack(alignment: .leading, spacing: Metric.roomy) {
                    VStack(alignment: .leading, spacing: Metric.tight) {
                        Text("Make time for your benefits")
                            .font(.title2.bold()).foregroundStyle(InterfacePalette.ink)
                        Text("A clear view of the deadlines recorded for your cards.")
                            .foregroundStyle(Color.secondary)
                    }
                    if deadlines.isEmpty {
                        CardWiseEmptyState(symbolName: "calendar.badge.checkmark", title: "No upcoming deadlines", message: wallet.cards.isEmpty ? "Add a card to see its recorded bonus deadlines here." : "There are no upcoming bonus deadlines recorded for your wallet. Credits with unknown reset dates are listed below.") {
                            if wallet.cards.isEmpty { Button("Add a card") { isAddingCard = true }.buttonStyle(.cardWisePrimary) }
                        }
                    } else {
                        ForEach(deadlines) { item in
                            if let card = wallet.card(withID: item.cardID) {
                                NavigationLink {
                                    CardBenefitsView(mode: .reviewing(card), presentation: .pushed)
                                } label: {
                                    DeadlineRow(item: item, cardName: organization.name(for: card), now: clock.date)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    undatedCredits
                }
                .padding(Metric.margin)
                .padding(.bottom, 70)
            }
            .background(InterfacePalette.page)
        }
        .navigationTitle("Benefit deadlines")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .sheet(isPresented: $isAddingCard) { AddCardView() }
    }

    private var undatedCredits: some View {
        VStack(alignment: .leading, spacing: Metric.snug) {
            ForEach(wallet.cards) { card in
                let credits = card.benefits().filter { $0.kind == .credit && $0.expiresOn == nil }
                if !credits.isEmpty {
                    VStack(alignment: .leading, spacing: Metric.tight) {
                        Label("Check the reset date", systemImage: "calendar.badge.questionmark")
                            .font(.headline)
                        Text(organization.name(for: card)).font(.subheadline.weight(.semibold))
                        ForEach(credits) { benefit in
                            Text(benefit.title).font(.subheadline)
                        }
                        Text("CardWise has no reset date or usage balance for these credits. Check your bank before making plans to use them.")
                            .font(.caption).foregroundStyle(Color.secondary)
                        NavigationLink("View card benefits") {
                            CardBenefitsView(mode: .reviewing(card), presentation: .pushed)
                        }
                        .frame(minHeight: Metric.minimumTarget)
                    }
                    .padding(Metric.regular)
                    .interfacePanel()
                }
            }
        }
    }
}

struct DeadlineRow: View {
    let item: BenefitDeadline
    let cardName: String
    var now: Date = Date()
    @Environment(\.dynamicTypeSize) private var typeSize

    private var needsAttention: Bool { item.date.timeIntervalSince(now) <= 14 * 86_400 || item.needsActivation }

    var body: some View {
        HStack(alignment: .top, spacing: Metric.snug) {
            if !typeSize.isAccessibilitySize {
                VStack(spacing: 3) {
                    Text(item.date, format: .dateTime.month(.abbreviated)).font(.caption.weight(.semibold))
                    Text(item.date, format: .dateTime.day()).font(.title2.bold()).monospacedDigit()
                }
                .foregroundStyle(InterfacePalette.blue)
                .frame(width: 54)
                .padding(.vertical, Metric.snug)
                .background(InterfacePalette.wash, in: RoundedRectangle(cornerRadius: Metric.tileRadius))
                .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: Metric.tight) {
                Text(item.urgency(asOf: now))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(needsAttention ? Color.cardWiseWarning : InterfacePalette.blue)
                Text(item.title).font(.headline).foregroundStyle(Color.primary)
                Text(cardName).font(.subheadline).foregroundStyle(Color.primary)
                Text(item.detail).font(.caption).foregroundStyle(Color.secondary)
                Text(item.date, format: .dateTime.month(.wide).day().year())
                    .font(.caption).foregroundStyle(Color.secondary)
                if item.needsActivation {
                    Label("Needs switching on", systemImage: "exclamationmark.circle")
                        .font(.caption.weight(.medium)).foregroundStyle(Color.cardWiseWarning)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(InterfacePalette.blue)
        }
        .padding(Metric.regular)
        .interfacePanel()
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the card's benefits")
    }
}
