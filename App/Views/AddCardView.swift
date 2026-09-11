import SwiftUI
import CardKit

/// Adding a card is *choosing* one, not describing one.
///
/// The old flow asked a person to type their bank, their card's name, its
/// colour, its material, every earn rate, both fees and a photo — which is a
/// spreadsheet wearing a form, and worse, it asked them for facts the app
/// already knows and has checked against the issuer's own page. This screen
/// asks one question instead: which card is it?
///
/// Three steps, and the third is a confirmation rather than data entry:
/// bank → exact product → `CardBenefitsView`. Describing a card by hand is
/// still possible, because the catalog is nine cards deep and somebody's
/// credit union is not in it, but it is a way out rather than the way in.
struct AddCardView: View {

    /// When set, whatever is chosen here replaces this card instead of joining
    /// it. "I picked the wrong one" should not leave the wrong one behind.
    var replacing: Card?

    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var isAddingByHand = false

    /// Snapshotted on purpose. `CardCatalog.entries` rebuilds its `Card` values
    /// — and their UUIDs — on every call, so reading it during `body` would
    /// churn every `ForEach` that touched it.
    @State private var entries = CardCatalog.entries
    @State private var issuers = CardCatalog.issuers

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var results: [CatalogEntry] {
        guard !trimmedQuery.isEmpty else { return [] }
        return entries.filter { $0.matches(trimmedQuery) }
    }

    var body: some View {
        NavigationStack {
            List {
                if trimmedQuery.isEmpty {
                    issuerSection
                } else if results.isEmpty {
                    noMatchSection
                } else {
                    resultsSection
                }

                if replacing == nil { byHandSection }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: "Bank, card name or nickname")
            .navigationTitle(replacing == nil ? "Add a card" : "Change card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $isAddingByHand) {
                CardEditorView(mode: .adding)
            }
        }
    }

    // MARK: - Choosing a bank

    private var issuerSection: some View {
        Section {
            ForEach(issuers) { issuer in
                NavigationLink {
                    productList(for: issuer)
                } label: {
                    HStack {
                        Text(issuer.fullName)
                        Spacer(minLength: 8)
                        Text("\(issuer.cardCount)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Which bank is it from?").textCase(nil)
        } footer: {
            Text("Or search for the card by name. \(catalogFreshness)")
        }
    }

    private func productList(for issuer: CatalogIssuer) -> some View {
        List {
            Section {
                ForEach(entries.filter { $0.card.issuer == issuer.name }) { entry in
                    NavigationLink {
                        CardBenefitsView(mode: .confirming(entry), replacing: replacing)
                    } label: {
                        CardProductRow(entry: entry)
                    }
                }
            } footer: {
                Text("Pick the exact card. Banks sell several that look alike and earn nothing alike.")
            }
        }
        .navigationTitle(issuer.fullName)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Searching

    private var resultsSection: some View {
        Section {
            ForEach(results) { entry in
                NavigationLink {
                    CardBenefitsView(mode: .confirming(entry), replacing: replacing)
                } label: {
                    CardProductRow(entry: entry)
                }
            }
        } header: {
            Text(results.count == 1 ? "One match" : "\(results.count) matches").textCase(nil)
        }
    }

    private var noMatchSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("No card called that yet")
                    .font(.subheadline.weight(.semibold))
                Text("The list is nine cards deep so far. Yours can still go in — you would just be the one saying what it earns.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - The way out

    private var byHandSection: some View {
        Section {
            Button {
                isAddingByHand = true
            } label: {
                Label("My card is not on the list", systemImage: "square.and.pencil")
            }
        } footer: {
            Text("You describe it, and it is ranked exactly the same way. Cards added by hand carry no source or date, because nobody checked them against the bank.")
        }
    }

    /// The seed rates carry the day somebody last read them off the issuer's
    /// own page. Stating it is the difference between a shortcut and a claim.
    private var catalogFreshness: String {
        let checked = CardCatalog.checkedOn.formatted(date: .abbreviated, time: .omitted)
        if CardCatalog.entries.first?.isStale() == true {
            return "Every card here was checked against the bank's own terms on \(checked), which is now old enough to be wrong."
        }
        return "Every card here was checked against the bank's own terms on \(checked)."
    }
}

/// One product in the list: which card it is, what it costs to hold, and the
/// two things it is best at. Enough to recognise a card without opening it.
struct CardProductRow: View {
    let entry: CatalogEntry

    private var headline: [String] {
        entry.card
            .benefits()
            .filter { $0.kind == .rewardRate && $0.relatedSpendingCategory != .base }
            .prefix(2)
            .map(\.title)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CardThumbnail(card: entry.card)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.card.name)
                    .font(.subheadline.weight(.semibold))
                Text(feeLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !headline.isEmpty {
                    Text(headline.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    private var feeLine: String {
        let network = entry.network.displayName
        if entry.card.annualFeeDollars == 0 {
            return "\(network), no annual fee"
        }
        return "\(network), \(money(entry.card.annualFeeDollars)) a year"
    }

    private func money(_ amount: Money) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "$\(amount)"
    }
}

#Preview {
    AddCardView()
        .environment(WalletStore.previewStore())
}
