import SwiftUI
import CardKit

/// "Did you use it?", asked once, about one suggestion, and never required.
///
/// This is the only part of the app that asks the user for anything, so it is
/// built to be ignorable. It appears in the same bottom inset as the undo
/// banner — transient, one line of content, gone the moment it is answered or
/// the day is over — rather than as a section on the wallet, because the
/// wallet holds cards and nothing else. Three buttons and no wrong answer:
/// "Not sure" is a real reply, and saying nothing at all is also fine.
///
/// Nothing downstream of this is load-bearing. Somebody who never taps it gets
/// exactly the app they had before: reminders that name the right card. All
/// this buys is the answer to "has that been worth anything to me", which is a
/// question only the person carrying it can settle.
struct FollowUpPromptView: View {

    let followUp: OpenRecommendation
    var onAnswer: (ImpactEventKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Did you use your \(followUp.snapshot.cardName)?")
                .font(.subheadline.weight(.semibold))
            Text(whenAndWhat)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("Yes") { onAnswer(.recommendationAccepted) }
                    .buttonStyle(.borderedProminent)
                Button("No") { onAnswer(.recommendationDeclined) }
                    .buttonStyle(.bordered)
                Button("Not sure") { onAnswer(.recommendationUncertain) }
                    .buttonStyle(.bordered)
                Spacer(minLength: 0)
            }
            .font(.subheadline)
            .controlSize(.small)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .padding(.horizontal, 20)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Names the card and the kind of shop, never the shop. Nothing in the
    /// ledger records where anybody was — see `ImpactEvent`.
    private var whenAndWhat: String {
        let when = followUp.shownAt.formatted(date: .omitted, time: .shortened)
        return "Suggested at \(when) for \(followUp.snapshot.category.displayName.lowercased())."
    }
}

/// The optional second question, and the only place a dollar figure is ever
/// asked for.
///
/// Optional twice over: this sheet is only reached by tapping Yes, and Skip
/// gets out of it without answering. What it buys is the difference between
/// "you took the advice" and "taking the advice earned you about $1.70 more
/// than your next best card would have" — and only the second of those is
/// worth anybody's attention.
struct PurchaseAmountView: View {

    let followUp: OpenRecommendation
    /// Hands back whatever the ledger made of the number, so the sheet can
    /// show it rather than sending the user somewhere to look.
    var onEnter: (Money) -> BenefitEstimate?

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var estimate: BenefitEstimate?
    @FocusState private var isFocused: Bool

    private var amount: Money? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let value = Decimal(string: trimmed), value > 0 else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                if let estimate {
                    resultSection(estimate)
                } else {
                    entrySection
                }
            }
            .navigationTitle(estimate == nil ? "What did you spend?" : "What that earned")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if estimate == nil {
                        Button("Skip") { dismiss() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if estimate == nil {
                        Button("Done") { submit() }
                            .disabled(amount == nil)
                            .fontWeight(.semibold)
                    } else {
                        Button("Done") { dismiss() }
                            .fontWeight(.semibold)
                    }
                }
            }
            .onAppear { isFocused = true }
        }
    }

    private var entrySection: some View {
        Section {
            HStack {
                Text("$")
                    .foregroundStyle(.secondary)
                TextField("0.00", text: $text)
                    .keyboardType(.decimalPad)
                    .focused($isFocused)
            }
        } header: {
            Text("Roughly, on your \(followUp.snapshot.cardName)").textCase(nil)
        } footer: {
            Text("A rough number is fine. It is used once, to estimate what that purchase earned, and it stays on this iPhone — nothing here reads your account or your statement.")
        }
    }

    private func resultSection(_ estimate: BenefitEstimate) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(estimate.rewardSummary)
                    .font(.title3.weight(.semibold))
                Text("Estimated, at \(rateText) and what you said a point is worth.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)

            if let line = estimate.incrementalSummary {
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("An estimate, not a statement. Nothing was discounted and no price changed — these are rewards the purchase should earn, which is a different thing from money saved.")
        }
    }

    private var rateText: String {
        let card = followUp.snapshot
        let currency = RewardCurrency(name: card.currencyName, style: card.style)
        return currency.formatted(rate: card.appliedRate)
    }

    private func submit() {
        guard let amount else { return }
        isFocused = false
        let result = onEnter(amount)
        withAnimation { estimate = result }
        // Nothing comes back only if the suggestion was already answered
        // elsewhere, in which case there is nothing left to show.
        if result == nil { dismiss() }
    }
}

#Preview("Banner") {
    let snapshot = RecommendationSnapshot(
        date: .now,
        cardID: UUID(),
        cardProductID: "amex-gold",
        cardName: "Amex Gold",
        currencyName: "Membership Rewards",
        style: .multiplier,
        appliedRate: 4,
        centsPerDollar: 4,
        alternateCardName: "Citi Double Cash",
        alternateCentsPerDollar: 2,
        category: .dining,
        confidence: .exact
    )
    return VStack {
        Spacer()
        FollowUpPromptView(followUp: OpenRecommendation(snapshot: snapshot, shownAt: .now)) { _ in }
    }
}
