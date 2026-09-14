import SwiftUI
import CardKit

/// What appears underneath a card once it is expanded: this quarter's rotating
/// status, everything the card is good for in plain English, how much of each
/// cap is left, and the coding quirks worth knowing.
///
/// The benefit list is `CardBenefit`, the same one `CardBenefitsView` renders,
/// so the card describes itself the same way wherever it is read.
struct CardDetailView: View {
    let card: Card

    @Environment(WalletStore.self) private var store

    private var art: CardArt { CardArt.art(for: card.artKey) }
    private var currentQuarter: Quarter { Quarter.containing(Date()) }

    var body: some View {
        VStack(alignment: .leading, spacing: Metric.roomy) {
            statsRow
            rotatingSection
            benefitsSection
            notesSection
            actionsSection
        }
        .padding(.horizontal, 4)
        .padding(.top, Metric.regular)
        .padding(.bottom, 28)
    }

    // MARK: - The three facts

    /// What the card is for and what it costs, before any of the detail. The
    /// two questions anybody actually opens a card to answer — see
    /// `Card.headlineStats`.
    private var statsRow: some View {
        HStack(spacing: Metric.snug) {
            ForEach(card.headlineStats()) { stat in
                StatTile(value: stat.value, label: stat.label, tint: art.accent)
            }
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
                        .foregroundStyle(.secondary)
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
        HStack(alignment: .top, spacing: 12) {
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
            Spacer(minLength: 8)
            Button(quarter.isActivated ? "Activated" : "Activate") {
                store.setActivated(!quarter.isActivated, cardID: card.id, quarter: quarter.quarter)
            }
            .buttonStyle(.borderedProminent)
            .tint(quarter.isActivated ? Color.secondary : art.accent)
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

        HStack(spacing: 12) {
            Button("Add this quarter") { isEnteringQuarter = true }
                .buttonStyle(.borderedProminent)
                .tint(art.accent)
            if let source = program.sourceURL, let url = URL(string: source) {
                Link("Look it up", destination: url)
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
        VStack(alignment: .leading, spacing: 18) {
            ForEach(benefitGroups, id: \.self) { group in
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle(group.displayName)
                    ForEach(benefits.filter { $0.group == group }) { benefit in
                        HStack(alignment: .top, spacing: Metric.snug) {
                        // The shelf's own colour and symbol, so a benefit is
                        // recognisable here as the same thing it is on the
                        // Benefits tab before its label is read.
                        CategoryIcon(
                            symbolName: group.symbolName,
                            tint: benefit.isActive ? group.tint : Color.secondary,
                            size: 32
                        )
                        VStack(alignment: .leading, spacing: 5) {
                            Text(benefit.title)
                                .font(.subheadline)
                            if let detail = benefit.detail {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    @State private var isShowingPreferExplainer = false
    @State private var isReviewingBenefits = false

    private var actionsSection: some View {
        HStack(spacing: 12) {
            Button {
                isReviewingBenefits = true
            } label: {
                Label("Benefits", systemImage: "list.bullet")
            }
            .buttonStyle(.bordered)
            .sheet(isPresented: $isReviewingBenefits) {
                // The live card, not the copy this view was handed — reopening
                // this after a save should show what was just saved. Changing
                // the card, or correcting it by hand, both live inside there;
                // neither is the thing a tap on a card should lead with.
                NavigationStack {
                    CardBenefitsView(mode: .reviewing(store.card(withID: card.id) ?? card))
                }
            }

            Button {
                if card.isPinned {
                    // Turning it off is a plain undo — no need to explain that again.
                    store.togglePin(card)
                } else {
                    isShowingPreferExplainer = true
                }
            } label: {
                // Short, because the alert does the explaining now and three
                // buttons have to share one row.
                Label(
                    card.isPinned ? "Preferred" : "Prefer",
                    systemImage: card.isPinned ? "star.fill" : "star"
                )
            }
            .buttonStyle(.bordered)
            .alert("Prefer this card?", isPresented: $isShowingPreferExplainer) {
                Button("Cancel", role: .cancel) {}
                Button("Prefer This Card") {
                    store.togglePin(card)
                }
            } message: {
                Text("Used only when two cards would earn the exact same amount. If one card earns more, that card still wins.")
            }

            Spacer(minLength: 8)

            Button(role: .destructive) {
                store.remove(card)
            } label: {
                Label("Remove", systemImage: "trash")
            }
            .buttonStyle(.bordered)
        }
        .font(.subheadline)
    }

    // MARK: - Pieces

    /// Sentence case, not tracked-out caps — see the note in CLAUDE.md about
    /// the design tells to avoid.
    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func capBar(_ cap: EarnCap, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: cap.fractionUsed)
                .tint(cap.isExhausted ? Color.cardWiseWarning : art.accent)
            Text(capText(cap))
                .font(.caption2)
                .foregroundStyle(cap.isExhausted ? Color.cardWiseWarning : Color.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) cap")
        .accessibilityValue(capText(cap))
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
