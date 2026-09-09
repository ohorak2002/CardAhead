import SwiftUI
import CardKit

/// Search the seeded catalog by issuer or card name, add it, then edit the
/// rules if the issuer has changed them.
struct AddCardView: View {

    @Environment(WalletStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""

    private var results: [Card] {
        CardCatalog.search(query)
    }

    var body: some View {
        NavigationStack {
            List {
                if results.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No match for \(query)")
                                .font(.subheadline.weight(.semibold))
                            Text("The catalog only seeds well-known cards. Add the closest one and edit its rules.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                ForEach(results) { card in
                    Button {
                        store.add(card)
                        dismiss()
                    } label: {
                        row(for: card)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: "Issuer or card name")
            .navigationTitle("Add a card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(for card: Card) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(CardArt.art(for: card.artKey).gradient)
                .frame(width: 44, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(card.displayName)
                    .font(.subheadline.weight(.semibold))
                Text(summary(for: card))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Adds this card to your wallet")
    }

    private func summary(for card: Card) -> String {
        var pieces = card.rules
            .filter { $0.category != .base }
            .sorted { $0.rate > $1.rate }
            .prefix(3)
            .map { "\(card.currency.formatted(rate: $0.rate)) \($0.category.displayName.lowercased())" }

        if let program = card.rotatingProgram {
            pieces.insert("\(card.currency.formatted(rate: program.rate)) rotating", at: 0)
        }
        if let base = card.rule(for: .base) {
            pieces.append("\(card.currency.formatted(rate: base.rate)) base")
        }
        return pieces.joined(separator: " · ")
    }
}

#Preview {
    AddCardView()
        .environment(WalletStore.previewStore())
}
