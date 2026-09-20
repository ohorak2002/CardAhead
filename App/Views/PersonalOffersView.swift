import SwiftUI
import CardKit

struct PersonalOffersView: View {
    @Environment(WalletStore.self) private var wallet
    var cardID: UUID? = nil
    @State private var adding = false
    @State private var editing: OfferSelection?
    @State private var redeeming: OfferSelection?
    private var cards: [Card] { wallet.cards.filter { cardID == nil || $0.id == cardID } }

    var body: some View {
        List {
            Section {
                Button("Add a reward or offer", systemImage: "plus") { adding = true }
                    .disabled(cards.isEmpty)
                Text("Personal offers are user-provided. Saving one here never enrolls it with your bank.").font(.caption)
            }
            ForEach(cards) { card in
                Section(card.displayName) {
                    ForEach(card.personalOffers ?? []) { offer in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(offer.title).font(.headline)
                            Text(offer.summary).font(.title3.bold())
                            Text(offer.enabled ? "Enabled · User-provided" : "Disabled · User-provided").font(.caption)
                            if let expires = offer.expiresOn { Text("Expires \(expires, style: .date)").font(.caption) }
                            Text("\(offer.usage(asOf: Date()).count) uses recorded this period").font(.caption)
                            if let cap = offer.maximumReward {
                                let used = offer.usage(asOf: Date()).reduce(Decimal.zero) { $0 + $1.receivedDollars }
                                ProgressView(value: min(used.doubleValue, cap.doubleValue), total: cap.doubleValue)
                                Text("$\(used.description) reported received of $\(cap.description) limit").font(.caption)
                            }
                            HStack {
                                Button("Edit") { editing = OfferSelection(card: card, offer: offer) }
                                Button(offer.enabled ? "Disable" : "Enable") {
                                    update(card, offer: offer) { $0.enabled.toggle() }
                                }
                                Button("Record use") { redeeming = OfferSelection(card: card, offer: offer) }
                            }.buttonStyle(.borderless)
                        }
                        .padding(.vertical, 8)
                        .swipeActions { Button("Delete", role: .destructive) {
                            var next = card
                            next.personalOffers?.removeAll { $0.id == offer.id }
                            wallet.replace(next)
                        } }
                    }
                }
            }
        }
        .navigationTitle("Personal rewards")
        .sheet(isPresented: $adding) { OfferEditorView(initialCardID: cardID) }
        .sheet(item: $editing) { item in OfferEditorView(initialCardID: item.card.id, existing: item.offer) }
        .sheet(item: $redeeming) { item in OfferRedemptionView(cardID: item.card.id, offerID: item.offer.id) }
    }

    private func update(_ card: Card, offer: PersonalOffer, change: (inout PersonalOffer) -> Void) {
        var next = card
        guard let index = next.personalOffers?.firstIndex(where: { $0.id == offer.id }) else { return }
        change(&next.personalOffers![index]); wallet.replace(next)
    }
}

private struct OfferSelection: Identifiable {
    let card: Card
    let offer: PersonalOffer
    var id: UUID { offer.id }
}

struct OfferEditorView: View {
    @Environment(WalletStore.self) private var wallet
    @Environment(\.dismiss) private var dismiss
    let initialCardID: UUID?
    var existing: PersonalOffer? = nil
    @State private var cardID: UUID?
    @State private var offer = PersonalOffer()
    @State private var names = ""
    @State private var step = 0
    @State private var loaded = false
    @State private var minimum = ""
    @State private var rewardCap = ""
    @State private var spendCap = ""
    @State private var hasStart = false
    @State private var hasExpiry = false
    @State private var start = Date()
    @State private var expiry = Date().addingTimeInterval(30 * 86400)

    private var prepared: PersonalOffer {
        var copy = offer
        copy.merchantNames = names.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        copy.minimumSpend = Decimal(string: minimum)
        copy.maximumReward = Decimal(string: rewardCap)
        copy.spendingCap = Decimal(string: spendCap)
        copy.startsOn = hasStart ? start : nil
        copy.expiresOn = hasExpiry ? expiry : nil
        return copy
    }
    private var error: String? {
        if cardID == nil { return "Choose a card." }
        for field in [minimum, rewardCap, spendCap] where !field.isEmpty && Decimal(string: field) == nil {
            return "Enter a valid dollar amount for each limit."
        }
        return prepared.validationError
    }
    var body: some View {
        NavigationStack {
            Form {
                Section { Text("Step \(step + 1) of 4").font(.caption).foregroundStyle(.secondary) }
                if step == 0 { whereStep }
                if step == 1 { rewardStep }
                if step == 2 { termsStep }
                if step == 3 { reviewStep }
            }
            .navigationTitle(existing == nil ? "Add a reward or offer" : "Edit offer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if step < 3 { Button("Next") { step += 1 } }
                    else { Button("Save") { save() }.disabled(error != nil) }
                }
                ToolbarItem(placement: .bottomBar) { if step > 0 { Button("Back") { step -= 1 } } }
            }
            .onAppear {
                guard !loaded else { return }; loaded = true
                cardID = initialCardID ?? wallet.cards.first?.id
                if let existing {
                    offer = existing; names = existing.merchantNames.joined(separator: ", ")
                    minimum = existing.minimumSpend?.description ?? ""
                    rewardCap = existing.maximumReward?.description ?? ""
                    spendCap = existing.spendingCap?.description ?? ""
                    hasStart = existing.startsOn != nil; start = existing.startsOn ?? start
                    hasExpiry = existing.expiresOn != nil; expiry = existing.expiresOn ?? expiry
                }
            }
        }
    }
    private var whereStep: some View {
        Section("Where does this apply?") {
            Picker("Which card?", selection: $cardID) {
                ForEach(wallet.cards) { Text($0.displayName).tag(Optional($0.id)) }
            }.disabled(existing != nil)
            TextField("Name this offer", text: $offer.title)
            Picker("Applies to", selection: $offer.scope) {
                Text("One merchant").tag(OfferScope.merchant)
                Text("A brand").tag(OfferScope.brand)
                Text("A category").tag(OfferScope.category)
                Text("Selected partners").tag(OfferScope.partners)
            }
            if offer.scope == .category {
                Picker("Category", selection: $offer.category) {
                    ForEach(SpendingCategory.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            } else {
                TextField("Exact names, separated by commas", text: $names, axis: .vertical)
                Text("Use exact map names or explicit brand aliases. Similar names are never automatically matched.").font(.caption)
            }
            Text("Illustrative example only: an offer at Acme Coffee applies to Acme Coffee, not every café.").font(.caption)
        }
    }
    private var rewardStep: some View {
        Section("What do you get?") {
            Picker("Reward", selection: $offer.reward) {
                Text("Percentage cash back").tag(OfferReward.cashBack)
                Text("Points per dollar").tag(OfferReward.points)
                Text("Fixed credit").tag(OfferReward.credit)
                Text("Spend X, get Y").tag(OfferReward.spendGet)
            }
            TextField(offer.reward == .cashBack ? "Percent" : offer.reward == .points ? "Points per dollar" : "Credit in dollars", value: $offer.value, format: .number)
                .keyboardType(.decimalPad)
            if offer.reward == .spendGet { TextField("Spend required in dollars", text: $minimum).keyboardType(.decimalPad) }
            Text("Illustrative example only: spend $50, get $10. This is not an available bank offer.").font(.caption)
        }
    }
    private var termsStep: some View {
        Group {
            Section("How it works") {
                Picker("Use", selection: $offer.recurrence) {
                    ForEach(OfferRecurrence.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                if offer.recurrence != .unlimited { Stepper("\(offer.usesPerPeriod) uses per period", value: $offer.usesPerPeriod, in: 1...1000) }
                Picker("Where you pay", selection: $offer.channel) {
                    Text("Online and in-store").tag(PurchaseChannel.both)
                    Text("Online only").tag(PurchaseChannel.online)
                    Text("In-store only").tag(PurchaseChannel.inStore)
                }
                Toggle("Enrollment required", isOn: $offer.enrollmentRequired)
                if offer.enrollmentRequired { Toggle("I enrolled through the issuer", isOn: $offer.enrolled) }
                Picker("Standard rewards", selection: $offer.stacking) {
                    Text("I don't know yet").tag(OfferStacking.unknown)
                    Text("Offer adds to them").tag(OfferStacking.addsToStandard)
                    Text("Offer replaces them").tag(OfferStacking.replacesStandard)
                }
                Text("Choose stacking only when supported by your terms. Multiple personal offers are never automatically combined.").font(.caption)
            }
            Section {
                DisclosureGroup("Limits and dates (optional)") {
                    if offer.reward != .spendGet { TextField("Minimum spend ($)", text: $minimum).keyboardType(.decimalPad) }
                    TextField("Maximum reward ($)", text: $rewardCap).keyboardType(.decimalPad)
                    if offer.reward == .cashBack || offer.reward == .points { TextField("Eligible spending cap ($)", text: $spendCap).keyboardType(.decimalPad) }
                    Toggle("Start date", isOn: $hasStart)
                    if hasStart { DatePicker("Starts", selection: $start, displayedComponents: .date) }
                    Toggle("Expiration", isOn: $hasExpiry)
                    if hasExpiry { DatePicker("Expires", selection: $expiry, displayedComponents: [.date, .hourAndMinute]) }
                }
            }
        }
    }
    private var reviewStep: some View {
        Section("Review your offer") {
            Text(prepared.title).font(.headline)
            Text(prepared.summary)
            Text("\(prepared.recurrence.rawValue.capitalized) · \(prepared.channel.rawValue)")
            if let value = prepared.minimumSpend { Text("Minimum spend: $\(value.description)") }
            if let value = prepared.maximumReward { Text("Maximum reward: $\(value.description)") }
            if let value = prepared.spendingCap { Text("Spending cap: $\(value.description)") }
            if let date = prepared.startsOn { Text("Starts \(date, style: .date)") }
            if let date = prepared.expiresOn { Text("Expires \(date, style: .date)") }
            Text(prepared.stacking == .unknown ? "Conditional until stacking is confirmed" : prepared.stacking == .addsToStandard ? "Adds to standard rewards" : "Replaces standard rewards")
            Text(prepared.enrollmentRequired ? (prepared.enrolled ? "You report enrollment with the issuer" : "Enrollment still required") : "You report no enrollment requirement")
            Text("User-provided. CardWise does not enroll you with the bank. Periods use calendar dates in UTC; enter separate offers for unusual issuer periods.").font(.caption)
            if let error { Text(error).foregroundStyle(.red) }
        }
    }
    private func save() {
        guard error == nil, let cardID, var card = wallet.card(withID: cardID) else { return }
        var offers = card.personalOffers ?? []
        if let index = offers.firstIndex(where: { $0.id == prepared.id }) { offers[index] = prepared }
        else { offers.append(prepared) }
        card.personalOffers = offers; wallet.replace(card); dismiss()
    }
}

private struct OfferRedemptionView: View {
    @Environment(WalletStore.self) private var wallet
    @Environment(ImpactStore.self) private var impact
    @Environment(\.dismiss) private var dismiss
    let cardID: UUID
    let offerID: UUID
    @State private var spent: Decimal = 0
    @State private var received: Decimal = 0
    var body: some View {
        NavigationStack {
            Form {
                TextField("Purchase amount ($)", value: $spent, format: .number).keyboardType(.decimalPad)
                TextField("Reward or credit actually received ($)", value: $received, format: .number).keyboardType(.decimalPad)
                Text("Your report, not independently verified. Enter the cash value received, not a points count.").font(.caption)
            }.navigationTitle("Record use")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") {
                        guard var card = wallet.card(withID: cardID), let index = card.personalOffers?.firstIndex(where: { $0.id == offerID }) else { return }
                        let redemption = OfferRedemption(purchaseDollars: spent, receivedDollars: received)
                        card.personalOffers![index].redemptions.append(redemption)
                        wallet.replace(card)
                        impact.recordReceived(redemption, productID: card.catalogProductID, category: card.personalOffers![index].scope == .category ? card.personalOffers![index].category : nil)
                        dismiss()
                    }.disabled(spent <= 0 || received < 0 || spent > 1_000_000 || received > 100_000) }
                }
        }
    }
}
