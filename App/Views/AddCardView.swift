import SwiftUI
import CardKit

/// Adding a card asks three questions, and none of them is a card number.
///
/// The app has no bank connection and never will in v1, so there is nothing to
/// import. What it needs is what the user already knows: roughly what the card
/// is, what colour it is, and what it pays extra on. The colour matters more
/// than it looks — it is how the user picks their card out of the stack, the
/// same way they pick it out of their wallet.
struct AddCardView: View {

    @Environment(WalletStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var issuer = ""
    @State private var cardName = ""
    @State private var artKey = "midnight"
    @State private var style: EarnStyle = .percent
    @State private var benefits: [DraftBenefit] = [
        DraftBenefit(category: .dining, rate: 3),
        DraftBenefit(category: .base, rate: 1)
    ]
    @State private var annualFee: Double = 0
    @State private var foreignFeePercent: Double = 0
    /// Snapshotted once: `CardCatalog.all` mints fresh ids on every call, which
    /// would churn the ForEach if it were read during body.
    @State private var catalog = CardCatalog.all

    struct DraftBenefit: Identifiable, Hashable {
        let id = UUID()
        var category: SpendingCategory
        var rate: Double
    }

    // MARK: - The card being described

    private var draft: Card {
        Card(
            issuer: issuer,
            name: cardName.trimmingCharacters(in: .whitespaces).isEmpty ? "Your card" : cardName,
            currency: RewardCurrency(
                name: style == .percent ? "Cash back" : "Points",
                centsPerUnit: 1.0,
                style: style
            ),
            rules: benefits
                .filter { $0.rate > 0 }
                .map { CategoryRule(category: $0.category, rate: $0.rate) },
            foreignTransactionFeePercent: foreignFeePercent,
            annualFeeDollars: Decimal(annualFee),
            artKey: artKey
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    CardFaceView(card: draft)
                        .frame(height: 170)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                }

                identitySection
                colourSection
                earnsSection

                Section {
                    Label(
                        "No card numbers, no bank login. The name and colour are only so you can tell your cards apart.",
                        systemImage: "lock"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add a card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") { save() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Which card is it?

    private var identitySection: some View {
        Section {
            TextField("Bank", text: $issuer)
            TextField("Card name", text: $cardName)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(catalog) { card in
                        Button(card.displayName) { fill(from: card) }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                    }
                }
                .padding(.vertical, 2)
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 0))
        } header: {
            Text("Which card is it?").textCase(nil)
        } footer: {
            Text("However you would describe it out loud. Tap a known card to fill it all in.")
        }
    }

    // MARK: - What does it look like?

    private var colourSection: some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                ForEach(CardArt.ordered) { art in
                    Button {
                        artKey = art.key
                    } label: {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(art.gradient)
                            .aspectRatio(1.6, contentMode: .fit)
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(artKey == art.key ? Color.primary : .clear, lineWidth: 2.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(art.label)
                    .accessibilityAddTraits(artKey == art.key ? [.isSelected] : [])
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("What does it look like?").textCase(nil)
        } footer: {
            Text("Pick the colour closest to the real card, so you can spot it in the stack.")
        }
    }

    // MARK: - What does it earn?

    private var earnsSection: some View {
        Section {
            Picker("Pays in", selection: $style) {
                Text("Cash back").tag(EarnStyle.percent)
                Text("Points").tag(EarnStyle.multiplier)
            }
            .pickerStyle(.segmented)

            ForEach($benefits) { $benefit in
                HStack {
                    Picker("Category", selection: $benefit.category) {
                        ForEach(sortedCategories, id: \.self) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
                    .labelsHidden()

                    Spacer(minLength: 8)

                    TextField("Rate", value: $benefit.rate, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 56)
                        .font(.body.monospacedDigit())

                    Text(style == .percent ? "%" : "x")
                        .foregroundStyle(.secondary)
                        .font(.body.monospacedDigit())
                }
            }
            .onDelete { benefits.remove(atOffsets: $0) }

            Button {
                benefits.append(DraftBenefit(category: .groceries, rate: 2))
            } label: {
                Label("Add another", systemImage: "plus")
            }

            HStack {
                Text("Annual fee")
                Spacer(minLength: 8)
                TextField("0", value: $annualFee, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 76)
                    .font(.body.monospacedDigit())
            }
            HStack {
                Text("Extra fee abroad")
                Spacer(minLength: 8)
                TextField("0", value: $foreignFeePercent, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                    .font(.body.monospacedDigit())
                Text("%").foregroundStyle(.secondary)
            }
        } header: {
            Text("What does it earn?").textCase(nil)
        } footer: {
            Text("One line for each thing it pays extra on. Swipe a line away to delete it.")
        }
    }

    private var sortedCategories: [SpendingCategory] {
        SpendingCategory.allCases
            .filter { $0 != .base }
            .sorted { $0.displayName < $1.displayName } + [.base]
    }

    // MARK: - Actions

    /// Filling from a known card is a shortcut, not an import. Everything it
    /// writes is still editable before the card is added.
    private func fill(from card: Card) {
        issuer = card.issuer
        cardName = card.name
        artKey = card.artKey
        style = card.currency.style
        annualFee = card.annualFeeDollars.doubleValue
        foreignFeePercent = card.foreignTransactionFeePercent
        benefits = card.rules.map { DraftBenefit(category: $0.category, rate: $0.rate) }
    }

    private func save() {
        var card = draft
        if card.rule(for: .base) == nil {
            card.rules.append(CategoryRule(category: .base, rate: 1))
        }
        store.add(card)
        dismiss()
    }
}

#Preview {
    AddCardView()
        .environment(WalletStore.previewStore())
}
