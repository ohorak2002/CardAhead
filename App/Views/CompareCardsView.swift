import SwiftUI
import CardKit

struct CompareCardsView: View {
    @Environment(WalletStore.self) private var wallet
    @Environment(OrganizationStore.self) private var organization
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var firstID: UUID?
    @State private var secondID: UUID?
    @State private var isAdding = false

    private var first: Card? { wallet.cards.first { $0.id == firstID } }
    private var second: Card? { wallet.cards.first { $0.id == secondID } }
    private let categories: [SpendingCategory] = [.dining, .groceries, .gas, .travel, .flights, .travelPortal, .base]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metric.roomy) {
                Text("Find the right fit")
                    .font(.title2.bold()).foregroundStyle(InterfacePalette.ink)
                Text("Compare what your cards earn today, alongside their fees and credits.")
                    .font(.subheadline).foregroundStyle(Color.secondary)
                if wallet.cards.count < 2 {
                    CardWiseEmptyState(symbolName: "rectangle.on.rectangle", title: "Two cards, one clear comparison", message: "Add another card to compare the cards you actually carry.") {
                        Button("Add a card") { isAdding = true }.buttonStyle(.cardWisePrimary)
                    }
                } else {
                    selectors
                    if let first, let second {
                        if !typeSize.isAccessibilitySize {
                            HStack(alignment: .top, spacing: Metric.snug) {
                                cardHeading(first)
                                cardHeading(second)
                            }
                        }
                        ForEach(categories, id: \.self) { category in
                            earningRow(category, first, second)
                        }
                        comparisonRow("Annual fee", first: first, second: second) { card in
                            Text(CardWiseFormat.money(card.annualFeeDollars) + " / year")
                                .font(.headline).monospacedDigit()
                        }
                        comparisonRow("Foreign transaction fee", first: first, second: second) { card in
                            Text(card.foreignTransactionFeePercent, format: .number.precision(.fractionLength(0...2)))
                                .font(.headline).monospacedDigit() + Text("%")
                        }
                        comparisonRow("Credits", first: first, second: second) { card in
                            let credits = card.benefits().filter { $0.kind == .credit }
                            VStack(alignment: .leading, spacing: Metric.tight) {
                                if credits.isEmpty {
                                    Text("No credit recorded").foregroundStyle(Color.secondary)
                                } else {
                                    ForEach(credits) { credit in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(credit.title).fontWeight(.semibold)
                                            if let detail = credit.detail { Text(detail).foregroundStyle(Color.secondary) }
                                        }
                                    }
                                }
                            }.font(.caption)
                        }
                        Text("Blue marks the higher ongoing estimated value between these two cards. Points use your valuations in Settings. Signup bonuses, annual fees, and untracked credits are not added to these earning rates. Your bank's terms and merchant coding still apply.")
                            .font(.footnote).foregroundStyle(Color.secondary)
                        ForEach([first, second]) { card in
                            NavigationLink("View \(organization.name(for: card)) benefits") {
                                CardBenefitsView(mode: .reviewing(card), presentation: .pushed)
                            }
                            .font(.subheadline).frame(minHeight: Metric.minimumTarget)
                        }
                    }
                }
            }
            .padding(Metric.margin)
            .padding(.bottom, 70)
        }
        .background(InterfacePalette.page)
        .navigationTitle("Compare cards")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .sheet(isPresented: $isAdding) { AddCardView() }
        .onAppear(perform: normalizeSelection)
        .onChange(of: wallet.cards.map(\.id)) { _, _ in normalizeSelection() }
    }

    private var selectors: some View {
        VStack(spacing: Metric.tight) {
            Picker("First card", selection: $firstID) {
                ForEach(wallet.cards.filter { $0.id != secondID }) { card in
                    Text(organization.name(for: card)).tag(Optional(card.id))
                }
            }
            .accessibilityIdentifier("compare.first")
            Picker("Compare with", selection: $secondID) {
                ForEach(wallet.cards.filter { $0.id != firstID }) { card in
                    Text(organization.name(for: card)).tag(Optional(card.id))
                }
            }
            .accessibilityIdentifier("compare.second")
        }
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metric.snug)
        .interfacePanel(tinted: true)
    }

    private func normalizeSelection() {
        if first == nil { firstID = wallet.cards.first?.id }
        if second == nil || secondID == firstID { secondID = wallet.cards.first { $0.id != firstID }?.id }
    }

    private func cardHeading(_ card: Card) -> some View {
        VStack(alignment: .leading, spacing: Metric.snug) {
            CardFaceView(card: card, photo: wallet.photo(for: card))
            Text(organization.name(for: card)).font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func earningRow(_ category: SpendingCategory, _ first: Card, _ second: Card) -> some View {
        let context = PurchaseContext(category: category, confidence: .categoryOnly, isTraveling: category.isTravelRelated, date: Date())
        let scores = RecommendationEngine().rank([first, second], in: context)
        let values = scores.map(\.effectiveCentsPerDollar)
        return comparisonRow(category.displayName, first: first, second: second) { card in
            if let score = scores.first(where: { $0.card.id == card.id }) {
                let better = values.count == 2 && score.effectiveCentsPerDollar > (values.min() ?? 0) + 0.000_001
                VStack(alignment: .leading, spacing: Metric.tight) {
                    Text(card.currency.formatted(rate: score.appliedRate))
                        .font(.title3.bold()).monospacedDigit()
                        .foregroundStyle(better ? InterfacePalette.blue : Color.primary)
                    if better { Label("Higher value", systemImage: "checkmark.circle.fill").font(.caption2).foregroundStyle(InterfacePalette.blue) }
                    Text(String(format: "%.2f¢ per $1", score.effectiveCentsPerDollar))
                        .font(.caption).monospacedDigit().foregroundStyle(Color.secondary)
                    if score.needsActivation { Text("Quarterly bonus not switched on").font(.caption2).foregroundStyle(Color.cardWiseWarning) }
                    if score.isCapExhausted { Text("Bonus cap used up").font(.caption2).foregroundStyle(Color.cardWiseWarning) }
                }
            }
        }
    }

    private func comparisonRow<Content: View>(_ title: String, first: Card, second: Card, @ViewBuilder content: @escaping (Card) -> Content) -> some View {
        VStack(alignment: .leading, spacing: Metric.snug) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            if typeSize.isAccessibilitySize {
                ForEach([first, second]) { card in
                    VStack(alignment: .leading, spacing: Metric.tight) {
                        Text(organization.name(for: card)).font(.subheadline.weight(.semibold))
                        content(card)
                    }
                    .padding(.vertical, Metric.tight)
                    .accessibilityElement(children: .combine)
                }
            } else {
                HStack(alignment: .top, spacing: Metric.snug) {
                    ForEach([first, second]) { card in
                        VStack(alignment: .leading, spacing: Metric.tight) {
                            Text(organization.name(for: card)).font(.caption).foregroundStyle(Color.secondary)
                            content(card)
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(Metric.regular)
        .interfacePanel()
    }
}
