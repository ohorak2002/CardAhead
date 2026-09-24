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

    /// How this screen got here, which decides whether it has to draw its own
    /// way out.
    ///
    /// SwiftUI will not say. `@Environment(\.isPresented)` is true for
    /// anything *inside* a sheet, and that includes a view pushed onto a stack
    /// the sheet itself owns — which is exactly the case that has to be told
    /// apart. So the presenter says.
    enum Presentation {
        /// Presented in its own `NavigationStack`, with nothing behind it.
        /// There is no back button, so Cancel is the only way out and this
        /// screen draws it.
        case sheet
        /// Pushed onto a stack that already shows a back chevron. Cancel
        /// beside it is the same button twice.
        case pushed
    }

    let mode: Mode
    /// Set when confirming a card that replaces one already in the wallet.
    var replacing: Card? = nil

    /// Defaults to `.sheet`, which is the safe half to be wrong about: a spare
    /// Cancel next to a back chevron is untidy, whereas a sheet without one
    /// leaves Done — which *saves* — as the only button on the screen.
    var presentation: Presentation = .sheet

    /// Called instead of `dismiss()` when popping is not enough to be finished
    /// — a push onto a stack that a sheet owns.
    ///
    /// A pushed view's `dismiss()` pops it. On this screen that meant tapping
    /// "Add" saved the card and then dropped you back on the list of products
    /// with the sheet still open — which looks exactly like nothing happened,
    /// and invites tapping Add a second time. The presenter passes its own
    /// dismiss instead.
    ///
    /// Not every push wants one. A `.pushed` screen opened straight off a tab
    /// is finished by popping, which is what `dismiss()` already does there.
    var onFinish: (() -> Void)? = nil

    @Environment(WalletStore.self) private var store
    @Environment(ImpactStore.self) private var impact
    @Environment(\.dismiss) private var dismiss

    /// Benefit ids the user has unticked. Ids rather than benefits, so a redraw
    /// between the tap and the save cannot drop the wrong row.
    @State private var setupCard: Card?
    @State private var adjustingSetup = false
    @State private var dropped: Set<String> = []
    @State private var isChangingCard = false
    @State private var isEditingByHand = false
    @State private var isChoosingPhoto = false

    /// A photo taken here but not saved yet.
    ///
    /// Held rather than written straight through, because a card being
    /// *confirmed* is not in the wallet yet — there is nothing to write it
    /// onto until Add is tapped, and somebody who backs out of this screen
    /// must not leave a photo file behind for a card that never existed.
    @State private var photoChange: PhotoChange = .unchanged

    private enum PhotoChange {
        case unchanged
        case removed
        case replaced(UIImage)
    }

    private var isConfirming: Bool {
        if case .confirming = mode { return true }
        return false
    }

    /// The live card while reviewing, so a change made elsewhere (activating a
    /// quarter, logging cap spend) shows here without reopening the screen.
    private var card: Card {
        switch mode {
        case .confirming(let entry): return setupCard ?? entry.card
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

    /// A card landing in the wallet. `.success` because this is the one thing
    /// in the app that completes something somebody set out to do — and it is
    /// fired here, at the button, rather than in the wallet watching its own
    /// count, because an undo also makes that count go up and the two must not
    /// feel the same.
    @State private var saved = Pulse()

    var body: some View {
        List {
            faceSection
            if isConfirming {
                Section {
                    Text(entry?.versionDescription ?? "User-provided card")
                    Button("My benefits are different") { adjustingSetup = true }
                }
            } else if let entry {
                Section("Standard benefits & adjustments") {
                    if card.hasCatalogUpdate {
                        Text("Catalog terms have changed or this wallet predates version tracking. Your saved terms remain in use until review.")
                        Button("Review update · preserve my adjustments") {
                            var next = card; next.reviewCatalogUpdate(); store.replace(next)
                        }
                    }
                    ForEach(entry.card.benefits()) { standard in
                        NavigationLink { BenefitTermsView(cardID: card.id, origin: standard.origin) } label: {
                            Text(standard.title + (card.isUserAdjusted(standard.origin) ? " · adjusted or disabled" : ""))
                        }
                    }
                    NavigationLink("Add a reward or offer") { PersonalOffersView(cardID: card.id) }
                }
            }
            ForEach(groups, id: \.self) { group in
                section(for: group)
            }
            if let entry, !(entry.card.standardBenefitOffers ?? []).isEmpty {
                Section("Standard credits · confirm account eligibility") {
                    ForEach(entry.card.standardBenefitOffers ?? []) { credit in
                        VStack(alignment: .leading) {
                            Text(credit.title).font(.headline)
                            Text(credit.summary)
                            Text("Not enabled. Review enrollment, channels, exclusions and stacking in Personal rewards after adding the card.").font(.caption)
                        }
                    }
                }
            }
            provenanceSection
            if !isConfirming { actionsSection }
        }
        .listStyle(.insetGrouped)
        // Only a card already held. Reading the benefits of one being added is
        // part of adding it, and counting both would count the same moment
        // twice under two different names.
        .onAppear { if !isConfirming { impact.recordBenefitsViewed(card) } }
        .sensoryFeedback(.success, trigger: saved)
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
                    // Only where nothing else gets you out. Pushed, this
                    // screen already has the system back chevron, and Cancel
                    // next to it is two controls for one job.
                    if presentation == .sheet {
                        Button("Cancel") { dismiss() }
                    }
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
        .sheet(isPresented: $adjustingSetup) {
            SetupBenefitAdjustmentsView(card: card) { setupCard = $0 }
        }
        .sheet(isPresented: $isChangingCard) {
            AddCardView(replacing: card)
        }
        .sheet(isPresented: $isEditingByHand) {
            CardEditorView(mode: .editing(card))
        }
        .sheet(isPresented: $isChoosingPhoto) {
            CardPhotoView(card: card) { image in
                photoChange = image.map { PhotoChange.replaced($0) } ?? .removed
            }
        }
    }

    // MARK: - The card itself

    private var faceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                CardFaceView(card: card, photo: faceImage)

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

            // Right here, under the card, rather than buried in the form the
            // catalog flow exists to avoid. Somebody who has just picked their
            // card off a list is exactly the person who wants it to look like
            // the one in their pocket.
            Button {
                isChoosingPhoto = true
            } label: {
                Label(hasPhoto ? "Change your card photo" : "Use a photo of your card", systemImage: "camera")
            }
        }
    }

    /// What the face is drawing right now: a photo taken on this screen and
    /// not saved yet, then the saved one, then nothing.
    private var faceImage: Image? {
        switch photoChange {
        case .replaced(let image): return Image(uiImage: image)
        case .removed: return nil
        case .unchanged: return store.photo(for: card)
        }
    }

    private var hasPhoto: Bool { faceImage != nil }

    /// The app must never let a drawn card pass for the bank's own artwork.
    /// `CardArtSource` decides which face is on screen, so it also decides
    /// which of these sentences is true — and it owns the sentences, in
    /// CardKit, where a test can check that the drawn one never claims to be
    /// the issuer's.
    private var artProvenance: String { artSource.provenanceLine }

    /// Which of the three faces is on screen *right now*, counting a photo
    /// taken on this screen and not saved yet. Reading it off `card` alone
    /// would caption a photograph of somebody's own card "Drawn by CardAhead",
    /// which is the exact thing this line exists to get right.
    private var artSource: CardArtSource {
        switch photoChange {
        case .replaced: return .userPhoto("")
        case .removed: return .drawn
        case .unchanged: return CardArtSource.resolve(for: card)
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
                Text(benefit.source == .user ? "User-provided" : benefit.verifiedOn == nil ? "Verification incomplete" : "Standard benefit")
                    .font(.caption2).foregroundStyle(.secondary)
                // A cap on something that is not paying yet is noise: the
                // quarterly $1,500 reads as money waiting for you when the
                // quarter has not even been switched on.
                if let cap = benefit.cap, benefit.isActive || cap.isExhausted {
                    Text(capText(cap))
                        .font(.caption2)
                        .foregroundStyle(cap.isExhausted ? Color.cardAheadWarning : Color.secondary)
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
                Label("My benefits are different", systemImage: "square.and.pencil")
            }
        } footer: {
            Text(card.isCatalogCard
                 ? "Changing the card keeps its place in your wallet. Individual adjustments are labeled user-provided and keep the product identity."
                 : "This card was described by hand, so the form is where its rates live.")
        }
    }

    // MARK: - Saving

    private func save() {
        saved.fire()
        var next = card.removingBenefits(ids: dropped)

        switch mode {
        case .confirming:
            if let old = replacing {
                // The photo change is applied *after* taking the old card's
                // place, not before: `takingWalletPlace(of:)` deliberately
                // carries the previous card's photo across, and would
                // otherwise overwrite the one just taken on this screen.
                next = next.takingWalletPlace(of: old)
                applyPhotoChange(to: &next)
                store.replace(next)
            } else {
                applyPhotoChange(to: &next)
                store.add(next)
            }
        case .reviewing:
            applyPhotoChange(to: &next)
            store.replace(next)
        }

        if let onFinish {
            onFinish()
        } else {
            dismiss()
        }
    }

    /// Writes the photo file and points the card at it, or deletes the one it
    /// had. `WalletStore.setPhoto` owns both halves so an edit cannot leave an
    /// orphaned image behind.
    private func applyPhotoChange(to card: inout Card) {
        switch photoChange {
        case .unchanged: break
        case .removed: store.setPhoto(nil, on: &card)
        case .replaced(let image): store.setPhoto(image, on: &card)
        }
    }

    // MARK: - Pieces

    private func capText(_ cap: EarnCap) -> String {
        if !cap.usageIsCurrent(asOf: Date()) { return "Usage unknown · \(money(cap.limitDollars)) \(cap.period.displayName) cap" }
        if cap.isExhausted {
            return "You have used the whole \(money(cap.limitDollars)) \(cap.period.displayName)."
        }
        return "\(money(cap.remainingDollars)) of \(money(cap.limitDollars)) \(cap.period.displayName) left"
    }

    private func money(_ amount: Money) -> String { CardAheadFormat.money(amount) }

    private func trim(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

#Preview("Confirming") {
    NavigationStack {
        CardBenefitsView(mode: .confirming(CardCatalog.entry(productID: "amex-gold")!))
    }
    .environment(WalletStore.previewStore())
    .environment(ImpactStore.previewStore())
}

#Preview("Reviewing") {
    NavigationStack {
        CardBenefitsView(mode: .reviewing(CardCatalog.chaseFreedomFlex))
    }
    .environment(WalletStore.previewStore())
    .environment(ImpactStore.previewStore())
}
