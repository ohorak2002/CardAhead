import SwiftUI
import CardKit

/// What the card is good for, in words, with tick boxes.
///
/// This is the last step of adding a card and the only editing most people will
/// ever do. It is deliberately *not* a second version of the old form: there is
/// nothing to type, no rate to work out, no cap to enter. A known card arrives
/// with its benefits already ticked, and the only question asked is whether any
/// of them are wrong.
///
/// Unticking one writes the correction straight into the card the ranking
/// engine reads — see `Card.removingBenefit(_:)`. There is no second list of
/// exceptions, so a card the user has corrected is ranked on the correction.
struct CardBenefitsView: View {

    enum Mode {
        /// Chosen from the list and not in the wallet yet.
        case confirming(CatalogEntry)
        /// Already in the wallet, opened from the card itself.
        case reviewing(Card)
    }

    let mode: Mode
    /// Set when confirming a card that replaces one already in the wallet.
    var replacing: Card? = nil

    /// Called instead of `dismiss()` when this screen was *pushed* rather than
    /// presented as a sheet.
    ///
    /// A pushed view's `dismiss()` pops it. On this screen that meant tapping
    /// "Add" saved the card and then dropped you back on the list of products
    /// with the sheet still open — which looks exactly like nothing happened,
    /// and invites tapping Add a second time. The presenter passes its own
    /// dismiss instead.
    var onFinish: (() -> Void)? = nil

    @Environment(WalletStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Benefit ids the user has unticked. Ids rather than benefits, so a redraw
    /// between the tap and the save cannot drop the wrong row.
    @State private var dropped: Set<String> = []
    @State private var isChangingCard = false
    @State private var isEditingByHand = false

    private var isConfirming: Bool {
        if case .confirming = mode { return true }
        return false
    }

    /// The live card while reviewing, so a change made elsewhere (activating a
    /// quarter, logging cap spend) shows here without reopening the screen.
    private var card: Card {
        switch mode {
        case .confirming(let entry): return entry.card
        case .reviewing(let card): return store.card(withID: card.id) ?? card
        }
    }

    private var entry: CatalogEntry? {
        switch mode {
        case .confirming(let entry): return entry
        case .reviewing(let card): return CardCatalog.entry(for: card)
        }
    }

    private var benefits: [CardBenefit] { card.benefits() }

    private var groups: [BenefitGroup] {
        var seen: Set<BenefitGroup> = []
        return benefits.map(\.group).filter { seen.insert($0).inserted }
    }

    var body: some View {
        List {
            faceSection
            ForEach(groups, id: \.self) { group in
                section(for: group)
            }
            provenanceSection
            if !isConfirming { actionsSection }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Benefits")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isConfirming {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(replacing == nil ? "Add" : "Use this card") { save() }
                        .fontWeight(.semibold)
                }
            } else {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { save() }
                        .fontWeight(.semibold)
                }
            }
        }
        // Unticking "3% at restaurants" on the wrong card must not untick it
        // on the right one. The ids match across products, so the only safe
        // thing to do with them when the product changes is forget them.
        .onChange(of: card.catalogProductID) { _, _ in
            dropped.removeAll()
        }
        .sheet(isPresented: $isChangingCard) {
            AddCardView(replacing: card)
        }
        .sheet(isPresented: $isEditingByHand) {
            CardEditorView(mode: .editing(card))
        }
    }

    // MARK: - The card itself

    private var faceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                CardFaceView(card: card, photo: store.photo(for: card))

                VStack(alignment: .leading, spacing: 4) {
                    Text(card.displayName)
                        .font(.headline)
                    Text(feeLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(artProvenance)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    /// The app must never let a drawn card pass for the bank's own artwork.
    /// `CardArtSource` decides which face is on screen, so it also decides
    /// which of these sentences is true.
    private var artProvenance: String {
        switch CardArtSource.resolve(for: card) {
        case .licensed(let asset):
            return asset.licence.attribution ?? "Artwork used with the issuer's permission."
        case .userPhoto:
            return "Your own photo of this card."
        case .drawn:
            return "Drawn by CardWise. Not the bank's artwork — we show that only where we have permission to."
        }
    }

    private var feeLine: String {
        var parts: [String] = []
        if let entry { parts.append(entry.network.displayName) }
        parts.append(card.annualFeeDollars == 0 ? "no annual fee" : "\(money(card.annualFeeDollars)) a year")
        if card.foreignTransactionFeePercent > 0 {
            parts.append("\(trim(card.foreignTransactionFeePercent))% extra abroad")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - The benefits

    private func section(for group: BenefitGroup) -> some View {
        Section {
            ForEach(benefits.filter { $0.group == group }) { benefit in
                row(for: benefit)
            }
        } header: {
            Text(group.displayName).textCase(nil)
        }
    }

    /// A benefit nobody can switch off is not a button.
    ///
    /// It used to be one, disabled — which greyed out the base rate and the
    /// quarterly bonus, two of the rows most worth reading, and told VoiceOver
    /// there was something there to press.
    @ViewBuilder
    private func row(for benefit: CardBenefit) -> some View {
        if benefit.isRemovable {
            Button {
                if dropped.contains(benefit.id) {
                    dropped.remove(benefit.id)
                } else {
                    dropped.insert(benefit.id)
                }
            } label: {
                content(for: benefit)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(dropped.contains(benefit.id) ? [] : [.isSelected])
        } else {
            content(for: benefit)
                .accessibilityElement(children: .combine)
        }
    }

    private func content(for benefit: CardBenefit) -> some View {
        let isKept = !dropped.contains(benefit.id)

        return HStack(alignment: .top, spacing: 11) {
            if benefit.isRemovable {
                Image(systemName: isKept ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isKept ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "lock")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 3)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(benefit.title)
                    .font(.subheadline.weight(.medium))
                    .strikethrough(!isKept)
                if let detail = benefit.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // A cap on something that is not paying yet is noise: the
                // quarterly $1,500 reads as money waiting for you when the
                // quarter has not even been switched on.
                if let cap = benefit.cap, benefit.isActive || cap.isExhausted {
                    Text(capText(cap))
                        .font(.caption2)
                        .foregroundStyle(cap.isExhausted ? Color.orange : Color.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(isKept ? Color.primary : Color.secondary)
        .padding(.vertical, 2)
    }

    // MARK: - Where this came from

    @ViewBuilder
    private var provenanceSection: some View {
        if let entry {
            Section {
                if let url = URL(string: entry.termsURL) {
                    Link(destination: url) {
                        Label("Check it on \(entry.issuerFullName)'s own page", systemImage: "arrow.up.right.square")
                    }
                    .font(.subheadline)
                }
                ForEach(entry.notModelled, id: \.self) { fact in
                    Text(fact)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Worth knowing").textCase(nil)
            } footer: {
                Text(entry.isStale()
                     ? "Read off the bank's own terms on \(checked(entry)), which is long enough ago to be wrong now. Check before you rely on it."
                     : "Read off the bank's own terms on \(checked(entry)). Banks change these without saying so — check against your own statement.")
            }
        } else {
            Section {
                Label(
                    "You described this card, so there is no source and no date behind these. Only you can keep them right.",
                    systemImage: "person.crop.square"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func checked(_ entry: CatalogEntry) -> String {
        entry.checkedOn.formatted(date: .abbreviated, time: .omitted)
    }

    // MARK: - Getting out

    private var actionsSection: some View {
        Section {
            if card.isCatalogCard {
                Button {
                    isChangingCard = true
                } label: {
                    Label("This is the wrong card", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            Button {
                isEditingByHand = true
            } label: {
                Label("Correct the details myself", systemImage: "square.and.pencil")
            }
        } footer: {
            Text(card.isCatalogCard
                 ? "Changing the card keeps its place in your wallet. Correcting the details by hand makes it your description, so it stops being dated against the bank's page."
                 : "This card was described by hand, so the form is where its rates live.")
        }
    }

    // MARK: - Saving

    private func save() {
        let next = card.removingBenefits(ids: dropped)

        switch mode {
        case .confirming:
            if let old = replacing {
                store.replace(next.takingWalletPlace(of: old))
            } else {
                store.add(next)
            }
        case .reviewing:
            store.replace(next)
        }

        if let onFinish {
            onFinish()
        } else {
            dismiss()
        }
    }

    // MARK: - Pieces

    private func capText(_ cap: EarnCap) -> String {
        if cap.isExhausted {
            return "You have used the whole \(money(cap.limitDollars)) \(cap.period.displayName)."
        }
        return "\(money(cap.remainingDollars)) of \(money(cap.limitDollars)) \(cap.period.displayName) left"
    }

    private func money(_ amount: Money) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "$\(amount)"
    }

    private func trim(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

#Preview("Confirming") {
    NavigationStack {
        CardBenefitsView(mode: .confirming(CardCatalog.entry(productID: "amex-gold")!))
    }
    .environment(WalletStore.previewStore())
}

#Preview("Reviewing") {
    NavigationStack {
        CardBenefitsView(mode: .reviewing(CardCatalog.chaseFreedomFlex))
    }
    .environment(WalletStore.previewStore())
}
