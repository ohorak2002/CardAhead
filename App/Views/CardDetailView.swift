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

    @ViewBuilder
    private var rotatingSection: some View {
        if let program = card.rotatingProgram,
           let quarter = program.quarter(currentQuarter) {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("This quarter")

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(quarter.categories.map(\.displayName).joined(separator: " · "))
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
                    .tint(quarter.isActivated ? .secondary : art.accent)
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

                if let cap = program.cap {
                    capBar(cap, label: "Rotating bonus")
                }
            }
        }
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

    private var actionsSection: some View {
        HStack(spacing: 12) {
            Button {
                store.togglePin(card)
            } label: {
                Label(
                    card.isPinned ? "Unpin" : "Pin",
                    systemImage: card.isPinned ? "pin.slash" : "pin"
                )
            }
            .buttonStyle(.bordered)

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
