import SwiftUI
import CardKit

/// What appears underneath a card once it is expanded.
///
/// The question this screen exists to answer is **"why do I carry this, and
/// when do I reach for it?"** — not "list everything the model knows". Those
/// are different screens, and the second one is a spreadsheet.
///
/// So it opens on the single most useful sentence anybody could read about a
/// card they already own — what it wins at *in this wallet* — and everything
/// below it is in descending order of how often somebody needs it: this
/// quarter's rotating bonus (the only thing here that earns money by being
/// tapped), what it pays for and where, the coding quirks worth knowing, then
/// the fee, then the three things you might do to the card itself.
///
/// **Three things it deliberately does not do.**
///
/// It does not repeat the rates. The card face and `RewardSummary` are
/// directly above this, always, and the summary already prints the top three
/// earning rules — so the old three-tile row here ("4x Dining", "4x
/// Groceries", "$325 Annual fee") was two-thirds a restatement of the line
/// four points above it. Only the fee was new, so only the fee survived, and
/// it is a line of text rather than a tile.
///
/// It does not use tiles at all. Three rounded rectangles with numbers in them
/// is the visual language of an analytics dashboard, and this is a wallet.
/// Hairlines and whitespace separate the sections instead.
///
/// And it does not make "Remove" look like a feature. The three actions were
/// three identical bordered buttons in one row, which gave deleting the card
/// the same weight as reading its benefits.
///
/// The benefit list is `CardBenefit`, the same one `CardBenefitsView` renders,
/// so the card describes itself the same way wherever it is read.
struct CardDetailView: View {
    let card: Card

    @Environment(WalletStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize

    private var currentQuarter: Quarter { Quarter.containing(Date()) }

    var body: some View {
        VStack(alignment: .leading, spacing: Metric.roomy) {
            bestForLine
            rotatingSection
            benefitsSection
            notesSection
            factsSection
            actionsSection
        }
        .padding(.horizontal, 4)
        .padding(.top, Metric.regular)
        .padding(.bottom, 28)
        .sensoryFeedback(.selection, trigger: pinned)
        .sensoryFeedback(.impact(weight: .medium), trigger: removed)
        .sensoryFeedback(.success, trigger: activated)
    }

    // MARK: - When to reach for it

    /// "Best for Dining" — and it has to be true of *this* wallet.
    ///
    /// `WalletInsights.bestCategory` ranks the whole wallet and only returns a
    /// category this card actually wins, so a 3x dining card sitting beside a
    /// 4x dining card gets no dining label. A small lie told on every scroll
    /// is still a lie, and being right about which card to reach for is the
    /// entire product.
    ///
    /// Nil is ordinary — a card that wins nothing in this wallet gets no line
    /// rather than a consolation one.
    @ViewBuilder
    private var bestForLine: some View {
        if let category = WalletInsights.bestCategory(for: card, in: store.cards) {
            HStack(spacing: Metric.snug) {
                CategoryIcon(symbolName: category.symbolName, tint: category.tint, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Best for \(category.displayName)")
                        .font(.headline)
                    Text("Nothing else in your wallet pays more here.")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Rotating

    @State private var isEnteringQuarter = false

    @ViewBuilder
    private var rotatingSection: some View {
        if let program = card.rotatingProgram {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("This quarter")

                switch program.status(for: currentQuarter) {
                case .bonus(let quarter):
                    publishedQuarter(quarter, in: program)
                case .unannounced:
                    unpublishedQuarter(program)
                case .none:
                    Text("Nothing extra on this card this quarter.")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }
            }
            .sheet(isPresented: $isEnteringQuarter) {
                RotatingQuarterEditor(
                    card: store.card(withID: card.id) ?? card,
                    quarter: currentQuarter
                )
            }
        }
    }

    @ViewBuilder
    private func publishedQuarter(_ quarter: RotatingQuarter, in program: RotatingProgram) -> some View {
        adaptiveRow {
            VStack(alignment: .leading, spacing: 4) {
                // The issuer's own wording when we have it: a quarter is often
                // wider than the categories this app can act on, and showing
                // only the narrow list reads as though the rest is not covered.
                Text(quarter.summary ?? quarter.categories.map(\.displayName).joined(separator: " · "))
                    .font(.subheadline.weight(.semibold))
                Text("\(card.currency.formatted(rate: program.rate)) until \(quarter.quarter.rawValue) ends")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: Metric.tight) }
            Button(quarter.isActivated ? "Activated" : "Activate") {
                // Only the on direction. Switching a bonus off is somebody
                // correcting a mistake, and a success chime for that would be
                // the app congratulating them on it — the same distinction
                // `WalletStore.setActivated` already makes for the ledger.
                if !quarter.isActivated { activated.fire() }
                store.setActivated(!quarter.isActivated, cardID: card.id, quarter: quarter.quarter)
            }
            .buttonStyle(.cardWiseSecondary)
            .disabled(quarter.isActivated)
        }

        if !quarter.isActivated {
            Label(
                "You are not earning this bonus until you activate it with the issuer.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(Color.cardWiseWarning)
        }

        if quarter.enteredByUser {
            Button("You added these. Change them") { isEnteringQuarter = true }
                .font(.caption)
                .frame(minHeight: Metric.minimumTarget)
        }

        if let cap = program.cap {
            capBar(cap, label: "Rotating bonus")
        }
    }

    /// The honest state, and the one that used to be filled with invented
    /// categories. Nobody has published this quarter, so the app says so and
    /// offers the only fix available to it.
    @ViewBuilder
    private func unpublishedQuarter(_ program: RotatingProgram) -> some View {
        Text("\(card.issuer) has not said what earns \(card.currency.formatted(rate: program.rate)) this quarter.")
            .font(.subheadline.weight(.semibold))

        Text("They announce it a quarter at a time, so nothing shipped with this app can know it. Until somebody tells us, this card is ranked on its everyday rates alone.")
            .font(.caption)
            .foregroundStyle(.secondary)

        adaptiveRow {
            Button("Add this quarter") { isEnteringQuarter = true }
                .buttonStyle(.cardWiseSecondary)
            if let source = program.sourceURL, let url = URL(string: source) {
                Link("Look it up", destination: url)
                    .frame(minHeight: Metric.minimumTarget)
            }
        }
        .font(.subheadline)
    }

    // MARK: - Benefits

    /// The same `CardBenefit` list the Benefits screen renders, minus the
    /// rotating programme — that one is above, with the button that switches
    /// it on. One description of the card, shown in two places, so the words
    /// here and the words there cannot drift apart.
    private var benefits: [CardBenefit] {
        card.benefits().filter { $0.origin != .rotating }
    }

    private var benefitGroups: [BenefitGroup] {
        var seen: Set<BenefitGroup> = []
        return benefits.map(\.group).filter { seen.insert($0).inserted }
    }

    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: Metric.roomy) {
            ForEach(benefitGroups, id: \.self) { group in
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle(group.displayName)
                    ForEach(benefits.filter { $0.group == group }) { benefit in
                        HStack(alignment: .top, spacing: Metric.snug) {
                            // The shelf's own colour and symbol, so a benefit
                            // is recognisable here as the same thing it is on
                            // the Benefits tab before its label is read.
                            CategoryIcon(
                                symbolName: group.symbolName,
                                tint: benefit.isActive ? group.tint : Color.secondary,
                                size: 32
                            )
                            VStack(alignment: .leading, spacing: 5) {
                                Text(benefit.title)
                                    .font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let detail = benefit.detail {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(Color.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                if let cap = benefit.cap, benefit.isActive || cap.isExhausted {
                                    capBar(cap, label: benefit.title)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var notesSection: some View {
        if !card.notes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Worth knowing")
                ForEach(card.notes) { note in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.category.displayName)
                            .font(.caption.weight(.semibold))
                        Text(note.text)
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - What it costs

    /// The fee and the floor rate, as two lines of text between two hairlines.
    ///
    /// **This is all that is left of the old three-tile row.** The other two
    /// tiles said what `RewardSummary` says four points above this view, in
    /// larger type, with an icon. The fee is the one fact on that row that
    /// appears nowhere else — and a fee is not a statistic to be celebrated in
    /// a rounded tile, it is a number you want to be able to find.
    private var factsSection: some View {
        VStack(spacing: 0) {
            Hairline()
            factRow("Annual fee", Self.dollars(card.annualFeeDollars))
            Hairline()
            factRow(
                "Everything else",
                "\(card.currency.formatted(rate: card.baseRate)) \(card.currency.unitNoun)"
            )
            if card.foreignTransactionFeePercent > 0 {
                Hairline()
                factRow(
                    "Abroad",
                    String(format: "%.0f%% foreign fee", card.foreignTransactionFeePercent)
                )
            }
            Hairline()
        }
    }

    private func factRow(_ label: String, _ value: String) -> some View {
        adaptiveRow {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
            if !typeSize.isAccessibilitySize { Spacer(minLength: Metric.snug) }
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Actions

    @State private var isShowingPreferExplainer = false
    /// Preferring a card is a small reversible toggle, so it gets the tick a
    /// picker gives. Removing one is not, so it gets a weight you notice.
    /// Switching a quarter's bonus on is the one thing on this screen that
    /// *earns* somebody money, so it gets the success pattern.
    @State private var pinned = Pulse()
    @State private var removed = Pulse()
    @State private var activated = Pulse()
    @State private var isReviewingBenefits = false

    /// **Two quiet actions and one destructive one, on separate rows.**
    ///
    /// This was three `.bordered` buttons sharing a line — "Benefits",
    /// "Prefer", "Remove" — at identical visual weight, which meant deleting
    /// the card read as the third feature of the screen. Removing a card is
    /// not a peer of reading its benefits; it goes underneath, in words rather
    /// than in a control, and it stays undoable for six seconds either way.
    private var actionsSection: some View {
        VStack(spacing: Metric.snug) {
            adaptiveRow {
                Button {
                    isReviewingBenefits = true
                } label: {
                    Label("Benefits", systemImage: "list.bullet")
                }
                .buttonStyle(CardWiseSecondaryButtonStyle())
                .sheet(isPresented: $isReviewingBenefits) {
                    // The live card, not the copy this view was handed —
                    // reopening this after a save should show what was just
                    // saved. Changing the card, or correcting it by hand, both
                    // live inside there; neither is the thing a tap on a card
                    // should lead with.
                    NavigationStack {
                        CardBenefitsView(mode: .reviewing(store.card(withID: card.id) ?? card))
                    }
                }

                Button {
                    if card.isPinned {
                        // Turning it off is a plain undo — no need to explain
                        // that again.
                        pinned.fire()
                        store.togglePin(card)
                    } else {
                        isShowingPreferExplainer = true
                    }
                } label: {
                    Label(
                        card.isPinned ? "Preferred" : "Prefer",
                        systemImage: card.isPinned ? "star.fill" : "star"
                    )
                }
                .buttonStyle(CardWiseSecondaryButtonStyle())
                .alert("Prefer this card?", isPresented: $isShowingPreferExplainer) {
                    Button("Cancel", role: .cancel) {}
                    Button("Prefer This Card") {
                        pinned.fire()
                        store.togglePin(card)
                    }
                } message: {
                    Text("Used only when two cards would earn the exact same amount. If one card earns more, that card still wins.")
                }
            }

            Button(role: .destructive) {
                removed.fire()
                store.remove(card)
            } label: {
                Text("Remove this card")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Metric.snug)
                    .frame(minHeight: Metric.minimumTarget)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.cardWiseError)
        }
    }

    private var adaptiveRow: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Metric.snug))
            : AnyLayout(HStackLayout(spacing: Metric.snug))
    }

    // MARK: - Pieces

    /// Sentence case, not tracked-out caps — see the note in CLAUDE.md about
    /// the design tells to avoid.
    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.secondary)
    }

    /// **The bar only appears once there is something to show.**
    ///
    /// A cap nobody has spent against draws a full-width empty track under
    /// every benefit — a progress bar at zero percent, which is a graphic
    /// saying nothing while occupying the width of the screen. The sentence
    /// under it already carries the number, and the moment a pound is spent
    /// the bar earns its place and appears.
    private func capBar(_ cap: EarnCap, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if cap.fractionUsed > 0 {
                ProgressView(value: cap.fractionUsed)
                    .tint(cap.isExhausted ? Color.cardWiseWarning : Color.cardWiseActionInk)
            }
            Text(capText(cap))
                .font(.caption2)
                .foregroundStyle(cap.isExhausted ? Color.cardWiseWarning : Color.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) cap")
        .accessibilityValue(capText(cap))
    }

    /// **Formatted here rather than by `RecommendationEngine.dollars`**,
    /// which is internal to CardKit — and deliberately so, since CardKit is
    /// tested on Linux where `maximumFractionDigits = 0` is ignored. This is
    /// the app, which only ever runs on iOS, so the same formatter behaves.
    /// `capText` below has always done it this way for the same reason.
    private static func dollars(_ amount: Money) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "$\(amount)"
    }

    private func capText(_ cap: EarnCap) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        let remaining = formatter.string(from: NSDecimalNumber(decimal: cap.remainingDollars)) ?? "$0"
        let limit = formatter.string(from: NSDecimalNumber(decimal: cap.limitDollars)) ?? "$0"
        if cap.isExhausted {
            return "Cap used up. Resets \(cap.period.displayName.replacingOccurrences(of: "per ", with: "next "))."
        }
        return "\(remaining) of \(limit) \(cap.period.displayName) left"
    }
}

#Preview {
    ScrollView {
        CardDetailView(card: CardCatalog.chaseFreedomFlex)
            .padding()
    }
    .environment(WalletStore.previewStore())
    .environment(ImpactStore.previewStore())
}
