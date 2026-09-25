import SwiftUI
import CardKit

/// Horizontal comparisons are separated by reward currency. No point valuation is implied.
struct BenefitGraphicsView: View {
    @Environment(WalletStore.self) private var wallet
    @State private var adding = false
    private var currencies: [String] { Array(Set(wallet.cards.map { $0.currency.name })).sorted() }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // The two things this screen lets you *do*, together at the top.
            // Adding is the main action; looking after what you have already
            // added is the occasional one, so it wears the quieter style — the
            // same blue family, a pale tinted bubble instead of a filled one.
            VStack(spacing: Metric.tight) {
                Button("Add a reward or offer", systemImage: "plus") { adding = true }.buttonStyle(.cardAheadPrimary)
                NavigationLink { PersonalOffersView() } label: {
                    Label("Manage personal offers", systemImage: "tag")
                }
                .buttonStyle(.cardAheadSecondary)
            }
            Text("Standard benefits & your adjustments")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(Color.cardAheadActionInk)
            Text("Rates describe eligible purchases. Map categories do not establish issuer eligibility.").font(.footnote).foregroundStyle(.secondary)
            ForEach(currencies, id: \.self) { currency in
                VStack(alignment: .leading, spacing: 16) {
                    // A shelf is a subject, not a row label. Giving it its
                    // own branded title treatment keeps it distinct from the
                    // card and rate titles beneath it.
                    Text(currency)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(Color.cardAheadActionInk)
                    ForEach(wallet.cards.filter { $0.currency.name == currency }) { card in
                        VStack(alignment: .leading, spacing: 12) {
                            // Card names are the title of each benefit panel.
                            // The larger light-blue treatment establishes that
                            // hierarchy without introducing a colour outside
                            // CardAhead's existing navy-and-blue palette.
                            Text(card.displayName)
                                .font(.system(.title2, design: .rounded).weight(.bold))
                                .foregroundStyle(Color.cardAheadLightBlue)
                            ForEach(card.benefits().filter { $0.kind == .rewardRate }) { benefit in
                                NavigationLink { BenefitTermsView(cardID: card.id, origin: benefit.origin) } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(benefit.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                        ProgressView(value: max(0, benefit.rate ?? 0), total: maximum(for: currency))
                                            .accessibilityHidden(true)
                                        Text(benefit.source == .user ? "User-provided adjustment" : benefit.verifiedOn == nil ? "Catalog · verification incomplete" : "Standard · source checked")
                                            .font(.caption).foregroundStyle(.secondary)
                                        if let cap = benefit.cap {
                                            if cap.usageIsCurrent(asOf: Date()) {
                                                ProgressView(value: cap.fractionUsed)
                                                Text("$\(cap.spentDollars.description) reported of $\(cap.limitDollars.description) \(cap.period.displayName)").font(.caption)
                                            } else { Text("Cap usage unknown · tap to enter").font(.caption) }
                                        }
                                    }.accessibilityElement(children: .combine)
                                }.buttonStyle(.plain)
                            }
                            NavigationLink("All benefits, sources & adjustments") {
                                CardBenefitsView(mode: .reviewing(card), presentation: .pushed)
                            }.font(.subheadline)
                        }.padding().background(.background, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            Text("Personal offers").font(.title2.bold())
            ForEach(wallet.cards) { card in
                ForEach(card.personalOffers ?? []) { offer in
                    NavigationLink { PersonalOffersView(cardID: card.id) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(offer.title).font(.headline)
                            Text(offer.summary).font(.title3.bold())
                            Text(card.displayName + " · User-provided").font(.caption)
                            if let expiry = offer.expiresOn { Text("Expires \(expiry, style: .date)").font(.caption) }
                            Text(offer.enabled ? "Enabled; conditions apply" : "Disabled").font(.caption)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding()
                            .background(.background, in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain)
                }
            }
        }.padding(.horizontal, Metric.margin)
            .sheet(isPresented: $adding) { OfferEditorView(initialCardID: nil) }
    }
    private func maximum(for currency: String) -> Double {
        max(1, wallet.cards.filter { $0.currency.name == currency }.flatMap(\.rules).map(\.rate).max() ?? 1)
    }
}

struct BenefitTermsView: View {
    @Environment(WalletStore.self) private var wallet
    let cardID: UUID
    let origin: BenefitOrigin
    @State private var rate: Double = 0
    @State private var capLimit: Decimal = 0
    @State private var spent: Decimal = 0
    @State private var hasCap = false
    @State private var period: CapPeriod = .annual
    @State private var loaded = false
    private var card: Card? { wallet.card(withID: cardID) }
    private var benefit: CardBenefit? { card?.benefits().first { $0.origin == origin } }
    var body: some View {
        Form {
            if let card {
                Section("Terms & source") {
                    Text(benefit?.title ?? "Disabled benefit").font(.headline)
                    if let detail = benefit?.detail { Text(detail) }
                    Text(card.isUserAdjusted(origin) ? "User-provided. Your changes are separate from the shared catalog." : "Standard product benefit; account terms and exclusions apply.")
                    if let entry = CardCatalog.entry(for: card), let url = URL(string: entry.termsURL) {
                        Link("Official issuer terms", destination: url)
                        if let date = entry.verifiedDate(for: origin), !card.isUserAdjusted(origin) {
                            Text("Verified \(date, style: .date)")
                        } else { Text("Current verification unavailable for this benefit.") }
                    }
                }
                if case .rule(let category) = origin {
                    Section("My benefits are different") {
                        NumberField("Rate", value: $rate)
                        Toggle("Spending cap", isOn: $hasCap)
                        if hasCap {
                            NumberField("Spending cap ($)", value: $capLimit)
                            Picker("Reset period", selection: $period) {
                                Text("Monthly").tag(CapPeriod.monthly)
                                Text("Quarterly").tag(CapPeriod.quarterly)
                                Text("Calendar year").tag(CapPeriod.annual)
                            }
                        }
                        Button("Save personal adjustment") {
                            var next = card
                            var rule = next.rule(for: category) ?? CategoryRule(category: category, rate: rate)
                            rule.rate = rate
                            let previousCap = rule.cap
                            rule.cap = hasCap ? EarnCap(limitDollars: capLimit, period: period, spentDollars: previousCap?.spentDollars ?? 0) : nil
                            if previousCap?.period == period { rule.cap?.usageUpdatedOn = previousCap?.usageUpdatedOn }
                            next.rules.removeAll { $0.category == category }; next.rules.append(rule)
                            next.adjustedBenefitIDs = Array(Set((next.adjustedBenefitIDs ?? []) + [origin.identifier]))
                            wallet.replace(next)
                        }.disabled(!rate.isFinite || rate < 0 || rate > 100 || (hasCap && capLimit <= 0))
                        if let benefit, benefit.isRemovable {
                            Button("Disable benefit") { wallet.replace(card.removingBenefit(benefit)) }
                        }
                    }
                    if card.rule(for: category)?.cap != nil {
                        Section("Usage this period") {
                            NumberField("Spend already counted ($)", value: $spent)
                            Button("Save reported usage") { wallet.setCapSpend(spent, cardID: card.id, category: category) }
                                .disabled(spent < 0)
                            Text("No transaction feed. Update usage each period; an unknown amount is never displayed as measured progress.").font(.caption)
                        }
                    }
                }
                if card.catalogProductID != nil {
                    Button("Restore current standard benefit") { var next = card; next.restoreBenefit(origin); wallet.replace(next) }
                }
            }
        }.navigationTitle("Benefit details")
            .keyboardDoneButton()
            .onAppear {
                guard !loaded else { return }; loaded = true
                rate = benefit?.rate ?? 0; hasCap = benefit?.cap != nil
                capLimit = benefit?.cap?.limitDollars ?? 0; spent = benefit?.cap?.spentDollars ?? 0
                period = benefit?.cap?.period ?? .annual
            }
    }
}
