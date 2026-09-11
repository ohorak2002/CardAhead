import SwiftUI
import CardKit

/// What appears underneath a card once it is expanded: every rule, how much of
/// each cap is left, this quarter's rotating status, and the perks.
struct CardDetailView: View {
    let card: Card

    @Environment(WalletStore.self) private var store

    private var art: CardArt { CardArt.art(for: card.artKey) }
    private var currentQuarter: Quarter { Quarter.containing(Date()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            rotatingSection
            rulesSection
            perksSection
            notesSection
            actionsSection
        }
        .padding(.horizontal, 4)
        .padding(.top, 16)
        .padding(.bottom, 28)
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
            .foregroundStyle(.orange)
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

    // MARK: - Rules

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Earns")
            ForEach(sortedRules) { rule in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(rule.category.displayName)
                            .font(.subheadline)
                        Spacer(minLength: 8)
                        Text(card.currency.formatted(rate: rule.rate))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                    }
                    if let note = rule.note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let cap = rule.cap {
                        capBar(cap, label: rule.category.displayName)
                    }
                }
            }
        }
    }

    private var sortedRules: [CategoryRule] {
        card.rules.sorted { lhs, rhs in
            if lhs.category == .base { return false }
            if rhs.category == .base { return true }
            if lhs.rate != rhs.rate { return lhs.rate > rhs.rate }
            return lhs.category.displayName < rhs.category.displayName
        }
    }

    // MARK: - Perks

    @ViewBuilder
    private var perksSection: some View {
        if !card.perks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Perks")
                ForEach(card.perks, id: \.self) { perk in
                    Label(perk.displayName, systemImage: perk.isTravelRelevant ? "airplane" : "checkmark.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
    @State private var isEditing = false

    private var actionsSection: some View {
        HStack(spacing: 12) {
            Button {
                isEditing = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .buttonStyle(.bordered)
            .sheet(isPresented: $isEditing) {
                // The live card, not the copy this view was handed — reopening
                // the editor after a save should show what was just saved.
                CardEditorView(mode: .editing(store.card(withID: card.id) ?? card))
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

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func capBar(_ cap: EarnCap, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: cap.fractionUsed)
                .tint(cap.isExhausted ? .orange : art.accent)
            Text(capText(cap))
                .font(.caption2)
                .foregroundStyle(cap.isExhausted ? .orange : .secondary)
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
}
