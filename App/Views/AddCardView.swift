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
///
/// **The flow was already right; the presentation was not.** It was a `List`
/// with `.insetGrouped`, `.searchable` and an inline navigation title — four
/// pieces of system furniture that between them made onboarding a card feel
/// like filling in a record. Onboarding should feel like the app doing
/// something for you. So the chrome is gone, the title is large type in the
/// content, and the rows are separated by hairlines rather than boxed one per
/// panel — the same language the map's results settled on, for the same
/// reason: a column of containers reads as a column of competing objects.
struct AddCardView: View {

    /// When set, whatever is chosen here replaces this card instead of joining
    /// it. "I picked the wrong one" should not leave the wrong one behind.
    var replacing: Card? = nil

    @Environment(WalletStore.self) private var store
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

    /// A card can legitimately be held twice, so this warns rather than
    /// forbids — but adding the same product a second time by accident is a
    /// much easier mistake than holding two of them.
    private func isAlreadyHeld(_ entry: CatalogEntry) -> Bool {
        store.cards.contains { $0.catalogProductID == entry.productID }
    }

    private var results: [CatalogEntry] {
        guard !trimmedQuery.isEmpty else { return [] }
        return entries.filter { $0.matches(trimmedQuery) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metric.roomy) {
                    title
                    CardWiseSearchField(
                        placeholder: "Bank, card name or nickname",
                        text: $query
                    )
                    .padding(.horizontal, Metric.margin)

                    if trimmedQuery.isEmpty {
                        issuerSection
                        byHandSection
                    } else if results.isEmpty {
                        noMatchSection
                        byHandSection
                    } else {
                        resultsSection
                    }
                }
                .padding(.top, Metric.snug)
                .padding(.bottom, Metric.section)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $isAddingByHand) {
                // Dismissing this screen tears its own sheet down with it, so
                // finishing the form lands back on the wallet rather than on
                // the list of cards it was not in.
                CardEditorView(mode: .adding, onFinish: { dismiss() })
            }
        }
    }

    /// A title in the content rather than in the navigation bar, which leaves
    /// the bar holding only Cancel.
    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(replacing == nil ? "Add a card" : "Change card")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            Text("Pick your bank, then the exact card. CardWise already knows what each one earns.")
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Metric.margin)
    }

    // MARK: - Choosing a bank

    private var issuerSection: some View {
        VStack(alignment: .leading, spacing: Metric.snug) {
            sectionLabel("Which bank is it from?")

            VStack(spacing: 0) {
                ForEach(Array(issuers.enumerated()), id: \.element.id) { index, issuer in
                    NavigationLink {
                        productList(for: issuer)
                    } label: {
                        HStack(spacing: Metric.snug) {
                            IssuerMonogram(name: issuer.fullName, size: 44)
                            Text(issuer.fullName)
                                .font(.body.weight(.medium))
                                .foregroundStyle(Color.primary)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: Metric.tight)
                            Text("\(issuer.cardCount)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(Color.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.secondary.opacity(0.5))
                        }
                        .padding(.vertical, Metric.snug)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < issuers.count - 1 {
                        Hairline(inset: 44 + Metric.snug)
                    }
                }
            }
            .padding(.horizontal, Metric.margin)

            Text(catalogFreshness)
                .font(.caption)
                .foregroundStyle(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Metric.margin)
        }
    }

    private func productList(for issuer: CatalogIssuer) -> some View {
        let products = entries.filter { $0.card.issuer == issuer.name }
        return ScrollView {
            VStack(alignment: .leading, spacing: Metric.snug) {
                Text("Pick the exact card. Banks sell several that look alike and earn nothing alike.")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Metric.margin)
                    .padding(.top, Metric.tight)

                productRows(products)
            }
            .padding(.bottom, Metric.section)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(issuer.fullName)
        .navigationBarTitleDisplayMode(.large)
    }

    /// Shared by the bank's list and the search results, so a card looks the
    /// same however you arrived at it.
    private func productRows(_ products: [CatalogEntry]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(products.enumerated()), id: \.element.id) { index, entry in
                NavigationLink {
                    CardPreviewView(
                        entry: entry,
                        replacing: replacing,
                        isAlreadyHeld: isAlreadyHeld(entry),
                        onFinish: { dismiss() }
                    )
                } label: {
                    CardProductRow(entry: entry, isAlreadyHeld: isAlreadyHeld(entry))
                }
                .buttonStyle(.plain)

                if index < products.count - 1 {
                    Hairline(inset: CardProductRow.thumbnailWidth + 12)
                }
            }
        }
        .padding(.horizontal, Metric.margin)
    }

    // MARK: - Searching

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: Metric.snug) {
            sectionLabel(results.count == 1 ? "One match" : "\(results.count) matches")
            productRows(results)
        }
    }

    private var noMatchSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No card called that yet")
                .font(.headline)
            Text("The list is nine cards deep so far. Yours can still go in — you would just be the one saying what it earns.")
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Metric.margin)
    }

    // MARK: - The way out

    /// **Quiet, and underneath.** Describing a card by hand is the escape
    /// hatch, not the route — it produces a card with no source and no date,
    /// which is exactly what the catalog exists to avoid. A secondary button
    /// under a line of explanation says that without a warning label.
    private var byHandSection: some View {
        VStack(alignment: .leading, spacing: Metric.tight) {
            Hairline()
                .padding(.bottom, Metric.tight)
            Button {
                isAddingByHand = true
            } label: {
                Label("My card is not on the list", systemImage: "square.and.pencil")
            }
            .buttonStyle(CardWiseSecondaryButtonStyle())

            Text("You describe it, and it is ranked exactly the same way. Cards added by hand carry no source or date, because nobody checked them against the bank.")
                .font(.caption)
                .foregroundStyle(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Metric.margin)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .padding(.horizontal, Metric.margin)
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
///
/// **The drawn card face is the anchor**, the same job the photograph does on
/// a map row. It is the one thing in the row that says "this is the gold one"
/// before a single word is read, and it costs nothing and needs no licence —
/// which is the whole argument for the app drawing its own faces.
struct CardProductRow: View {
    let entry: CatalogEntry
    var isAlreadyHeld: Bool = false

    /// Shared with the list that draws the hairlines between these rows, so
    /// the rule lines up with the text rather than with a guess.
    static let thumbnailWidth: CGFloat = 64

    private var headline: [String] {
        entry.card
            .benefits()
            .filter { $0.kind == .rewardRate && $0.relatedSpendingCategory != .base }
            .prefix(2)
            .map(\.title)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Sized by its own `width`, not by an outer `.frame`.
            // `CardThumbnail` sets its height from an aspect ratio, and this
            // repo has already lost a whole wallet layout to a frame fighting
            // an `aspectRatio` over who decides the width.
            CardThumbnail(card: entry.card, width: Self.thumbnailWidth)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.card.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                    if isAlreadyHeld {
                        Text("In your wallet")
                            .font(.caption2)
                            .foregroundStyle(Color.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.cardWiseHairline, in: Capsule())
                    }
                }
                Text(feeLine)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                if !headline.isEmpty {
                    Text(headline.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.secondary.opacity(0.5))
                .padding(.top, 4)
        }
        .padding(.vertical, Metric.snug)
        .contentShape(Rectangle())
    }

    private var feeLine: String {
        let network = entry.network.displayName
        if entry.card.annualFeeDollars == 0 {
            return "\(network), no annual fee"
        }
        return "\(network), \(money(entry.card.annualFeeDollars)) a year"
    }

    private func money(_ amount: Money) -> String { CardWiseFormat.money(amount) }
}

#Preview {
    AddCardView()
        .environment(WalletStore.previewStore())
        .environment(ImpactStore.previewStore())
}
