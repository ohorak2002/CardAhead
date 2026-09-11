import SwiftUI
import PhotosUI
import CardKit

/// One form, two jobs: describing a new card and correcting one already in the
/// wallet. They ask exactly the same questions, so they are the same screen.
///
/// Editing is not "add again". The form owns six things — the name, the look,
/// the material, what it pays, the fees, the photo — and an edit must leave
/// everything else on the card exactly where it was. Rebuilding the card from
/// the form would quietly throw away the rotating programme, the perks, the
/// coding notes, an open signup bonus, the pin, and the cap progress the user
/// typed in by hand. So an edit is applied *onto* the original.
struct CardEditorView: View {

    enum Mode: Equatable {
        case adding
        case editing(Card)

        var existingCard: Card? {
            if case .editing(let card) = self { return card }
            return nil
        }
    }

    let mode: Mode

    @Environment(WalletStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var issuer = ""
    @State private var cardName = ""
    @State private var artKey = "midnight"
    @State private var finish: CardFinish = .matte
    @State private var style: EarnStyle = .percent
    @State private var benefits: [DraftBenefit] = []
    @State private var annualFee: Double = 0
    @State private var foreignFeePercent: Double = 0

    @State private var pickedPhoto: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var photoChange: PhotoChange = .unchanged
    @State private var hasLoadedExisting = false

    /// Snapshotted once: `CardCatalog.all` mints fresh ids on every call, which
    /// would churn the ForEach if it were read during body.
    @State private var catalog = CardCatalog.all

    /// Leaving a photo alone is different from removing it — only one of those
    /// should delete the file on disk.
    private enum PhotoChange {
        case unchanged
        case replaced
        case removed
    }

    struct DraftBenefit: Identifiable, Hashable {
        let id = UUID()
        var category: SpendingCategory
        var rate: Double
    }

    private var isEditing: Bool { mode.existingCard != nil }

    // MARK: - The card as described right now

    /// Used for the live preview, and as the starting point when adding.
    private var draft: Card {
        apply(to: mode.existingCard ?? Card(
            issuer: "",
            name: "Your card",
            artKey: artKey
        ))
    }

    /// The form's six fields, written onto a card, leaving the rest untouched.
    private func apply(to original: Card) -> Card {
        var card = original
        card.issuer = issuer
        let trimmed = cardName.trimmingCharacters(in: .whitespaces)
        card.name = trimmed.isEmpty ? (isEditing ? original.name : "Your card") : trimmed
        card.artKey = artKey
        card.finish = finish
        card.foreignTransactionFeePercent = foreignFeePercent
        card.annualFeeDollars = Decimal(annualFee)

        // Keep the currency's own name and the user's valuation. Renaming
        // "Amex points" to "Points" would split it from its group in Settings,
        // and resetting centsPerUnit would silently undo a valuation they set.
        let keepsStyle = original.currency.style == style
        card.currency = RewardCurrency(
            name: keepsStyle && !original.currency.name.isEmpty
                ? original.currency.name
                : (style == .percent ? "Cash back" : "Points"),
            centsPerUnit: keepsStyle ? original.currency.centsPerUnit : 1.0,
            style: style
        )

        // Caps and coding notes belong to the rule, not to the form. Changing a
        // rate must not reset the $6,000 of grocery spend someone logged.
        card.rules = benefits
            .filter { $0.rate > 0 }
            .map { draft in
                let existing = original.rule(for: draft.category)
                return CategoryRule(
                    category: draft.category,
                    rate: draft.rate,
                    cap: existing?.cap,
                    note: existing?.note
                )
            }
        return card
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    CardFaceView(card: draft, photo: previewPhoto)
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
            .task(id: pickedPhoto) { await loadPickedPhoto(pickedPhoto) }
            .onAppear(perform: loadExistingOnce)
            .navigationTitle(isEditing ? "Edit card" : "Add a card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "Save" : "Add") { save() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    /// While editing, the existing photo shows until the user changes it.
    private var previewPhoto: Image? {
        switch photoChange {
        case .removed: return nil
        case .replaced: return photo.map(Image.init(uiImage:))
        case .unchanged:
            if let photo { return Image(uiImage: photo) }
            return mode.existingCard.flatMap(store.photo(for:))
        }
    }

    // MARK: - Which card is it?

    private var identitySection: some View {
        Section {
            TextField("Bank", text: $issuer)
            TextField("Card name", text: $cardName)

            // A shortcut for describing a card you do not know by heart. It is
            // noise once the card exists and its rates have been corrected.
            if !isEditing {
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
            }
        } header: {
            Text("Which card is it?").textCase(nil)
        } footer: {
            Text(isEditing
                 ? "However you would describe it out loud."
                 : "However you would describe it out loud. Tap a known card to fill it all in.")
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

            Picker("Material", selection: $finish) {
                ForEach(CardFinish.allCases, id: \.self) { finish in
                    Text(finish.displayName).tag(finish)
                }
            }
            .pickerStyle(.segmented)

            PhotosPicker(selection: $pickedPhoto, matching: .images) {
                Label(
                    previewPhoto == nil ? "Use a photo of your card" : "Choose a different photo",
                    systemImage: "camera"
                )
            }
            if previewPhoto != nil {
                Button("Remove photo", role: .destructive) {
                    photo = nil
                    pickedPhoto = nil
                    photoChange = .removed
                }
            }
        } header: {
            Text("What does it look like?").textCase(nil)
        } footer: {
            Text("Pick the colour and material closest to the real card, so you can spot it in the stack. A photo of your own card is an exact match — it stays on this device and is never uploaded. We cannot ship the banks' own artwork; Apple Wallet only shows it because the bank sends it.")
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
            Text(isEditing
                 ? "Changing a rate keeps whatever spend you have already logged against its cap."
                 : "One line for each thing it pays extra on. Swipe a line away to delete it.")
        }
    }

    private var sortedCategories: [SpendingCategory] {
        SpendingCategory.allCases
            .filter { $0 != .base }
            .sorted { $0.displayName < $1.displayName } + [.base]
    }

    // MARK: - Loading and saving

    /// `onAppear` can fire more than once; the form must not be reset under
    /// someone who is halfway through editing it.
    private func loadExistingOnce() {
        guard !hasLoadedExisting else { return }
        hasLoadedExisting = true

        guard let card = mode.existingCard else {
            benefits = [
                DraftBenefit(category: .dining, rate: 3),
                DraftBenefit(category: .base, rate: 1)
            ]
            return
        }
        issuer = card.issuer
        cardName = card.name
        artKey = card.artKey
        finish = card.appearance
        style = card.currency.style
        annualFee = card.annualFeeDollars.doubleValue
        foreignFeePercent = card.foreignTransactionFeePercent
        benefits = card.rules
            .sorted { lhs, rhs in
                if lhs.category == .base { return false }
                if rhs.category == .base { return true }
                return lhs.rate > rhs.rate
            }
            .map { DraftBenefit(category: $0.category, rate: $0.rate) }
    }

    private func loadPickedPhoto(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else { return }
        photo = image
        photoChange = .replaced
    }

    /// Filling from a known card is a shortcut, not an import. Everything it
    /// writes is still editable before the card is saved.
    private func fill(from card: Card) {
        issuer = card.issuer
        cardName = card.name
        artKey = card.artKey
        finish = card.appearance
        style = card.currency.style
        annualFee = card.annualFeeDollars.doubleValue
        foreignFeePercent = card.foreignTransactionFeePercent
        benefits = card.rules.map { DraftBenefit(category: $0.category, rate: $0.rate) }
    }

    private func save() {
        if let existing = mode.existingCard {
            var card = apply(to: existing)
            switch photoChange {
            case .unchanged: break
            case .removed: store.setPhoto(nil, on: &card)
            case .replaced: store.setPhoto(photo, on: &card)
            }
            store.replace(card)
        } else {
            var card = draft
            if card.rule(for: .base) == nil {
                card.rules.append(CategoryRule(category: .base, rate: 1))
            }
            if case .replaced = photoChange {
                store.setPhoto(photo, on: &card)
            }
            store.add(card)
        }
        dismiss()
    }
}

#Preview("Adding") {
    CardEditorView(mode: .adding)
        .environment(WalletStore.previewStore())
}

#Preview("Editing") {
    CardEditorView(mode: .editing(CardCatalog.amexGold))
        .environment(WalletStore.previewStore())
}
