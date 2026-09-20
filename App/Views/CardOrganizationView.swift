import SwiftUI
import CardKit

struct CardOrganizationView: View {
    @Environment(WalletStore.self) private var wallet
    @Environment(OrganizationStore.self) private var organization
    @Environment(\.dismiss) private var dismiss
    @State private var isReordering = false

    var body: some View {
        NavigationStack {
            List {
                if let failure = organization.failure {
                    Section { Label(failure, systemImage: "exclamationmark.triangle") }
                }
                Section {
                    ForEach(wallet.cards) { card in
                        NavigationLink {
                            CardOrganizationEditor(cardID: card.id)
                        } label: {
                            HStack(spacing: Metric.snug) {
                                CardThumbnail(card: card, photo: wallet.photo(for: card))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(organization.name(for: card)).font(.headline)
                                    if organization.name(for: card) != card.displayName {
                                        Text(card.displayName).font(.caption).foregroundStyle(Color.secondary)
                                    }
                                    if card.isPinned { Label("Preferred in a tie", systemImage: "star.fill").font(.caption).foregroundStyle(InterfacePalette.blue) }
                                    if organization.isHidden(card) { Label("Hidden from wallet", systemImage: "eye.slash").font(.caption).foregroundStyle(Color.secondary) }
                                }
                                .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, Metric.tight)
                        }
                        .accessibilityIdentifier("organization.card.\(card.id.uuidString)")
                    }
                } footer: {
                    Text("Give cards a nickname or hide faces you rarely need. Hidden cards remain in your wallet data and can still be recommended. Your preferred card breaks ties; a better earning card still wins.")
                }
                if wallet.cards.count > 1 {
                    Section {
                        Button { isReordering = true } label: { Label("Reorder cards", systemImage: "arrow.up.arrow.down") }
                    }
                }
            }
            .navigationTitle("Organize cards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $isReordering) { WalletReorderView() }
        }
    }
}

private struct CardOrganizationEditor: View {
    let cardID: UUID
    @Environment(WalletStore.self) private var wallet
    @Environment(OrganizationStore.self) private var organization
    @Environment(\.dismiss) private var dismiss
    @State private var nickname = ""
    @State private var hidden = false
    @State private var preferred = false
    @State private var loaded = false

    var body: some View {
        Form {
            if let card = wallet.card(withID: cardID) {
                Section {
                    HStack(spacing: Metric.snug) {
                        CardThumbnail(card: card, photo: wallet.photo(for: card))
                        Text(card.displayName).font(.headline)
                    }
                    .padding(.vertical, Metric.tight)
                }
                Section("Nickname") {
                    TextField("e.g. Everyday dining", text: $nickname)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("card.nickname")
                    Text("Only the label in CardWise changes. Your card's name and artwork stay as they are.")
                        .font(.caption).foregroundStyle(Color.secondary)
                }
                Section {
                    Toggle("Prefer this card", isOn: $preferred)
                        .accessibilityIdentifier("card.preferred")
                } footer: {
                    Text("Use this as your default when cards tie. CardWise still recommends a card with a better estimated value.")
                }
                Section {
                    Toggle("Hide from wallet", isOn: $hidden)
                        .accessibilityIdentifier("card.hidden")
                } footer: {
                    Text("Hides its face from Home and Wallet. Benefits and recommendations still include this card. You can show it again here anytime.")
                }
                if let failure = organization.failure { Section { Text(failure).foregroundStyle(Color.cardWiseError) } }
            } else {
                Text("This card was removed from your wallet.")
            }
        }
        .navigationTitle("Card preferences")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save).disabled(wallet.card(withID: cardID) == nil)
            }
        }
        .onAppear {
            guard !loaded, let card = wallet.card(withID: cardID) else { return }
            nickname = organization.preferences.nicknames[cardID.uuidString] ?? ""
            hidden = organization.isHidden(card)
            preferred = card.isPinned
            loaded = true
        }
    }

    private func save() {
        guard let card = wallet.card(withID: cardID) else { return }
        guard organization.update({ value in
            value.setNickname(nickname, for: cardID)
            if hidden { value.hiddenCardIDs.insert(cardID) } else { value.hiddenCardIDs.remove(cardID) }
        }) else { return }
        // Explicitly preferring one card uses the existing tie-break behavior.
        if preferred && !card.isPinned { wallet.preferOnly(cardID) }
        if !preferred && card.isPinned { wallet.togglePin(card) }
        dismiss()
    }
}
