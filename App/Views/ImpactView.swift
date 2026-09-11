import SwiftUI
import CardKit

/// Has this app been worth carrying?
///
/// Behind Settings rather than on the wallet, because it is a question people
/// ask occasionally and a number nobody should be looking at daily. The wallet
/// answers "which card", and that is all it should answer.
///
/// **What this screen will not say.** Not "saved". Nothing was discounted, no
/// price was lowered, and this app has never seen a transaction — every figure
/// here rests on a number somebody typed in and a point valuation they set
/// themselves. The headline is what *choosing differently* is estimated to
/// have earned over the next best card in the same wallet, which is the only
/// part of a reward an app can take any credit for. A card earning 4x would
/// have earned 4x whether or not anybody was told about it; being told is
/// worth the gap, not the total.
struct ImpactView: View {

    @Environment(ImpactStore.self) private var impact

    var body: some View {
        List {
            if impact.isRecording {
                if impact.summary.hasAnythingToShow {
                    valueSection
                    adviceSection
                    quietSection
                } else {
                    nothingYetSection
                }
            }
            recordingSection
        }
        .navigationTitle("Your impact")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summary: ImpactSummary { impact.summary }

    // MARK: - What the choices earned

    private var valueSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(dollars(summary.estimatedIncrementalValueCents))
                    .font(.largeTitle.weight(.semibold))
                    .monospacedDigit()
                Text(summary.priced == 0
                     ? "Nothing priced yet."
                     : "over your next best card, across \(purchaseCount)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

            if summary.priced > 0 {
                LabeledContent("Estimated rewards earned", value: dollars(summary.estimatedRewardValueCents))
                    .monospacedDigit()
            }
        } header: {
            Text("Estimated extra rewards").textCase(nil)
        } footer: {
            Text("An estimate, and only of the purchases you put a number on. Not savings: nothing was discounted and no price changed. The figure above is the gap between the card you were told to use and the next best one you already own — the part being told about actually accounts for.")
        }
    }

    private var purchaseCount: String {
        summary.priced == 1 ? "one purchase" : "\(summary.priced) purchases"
    }

    // MARK: - Whether the advice landed

    @ViewBuilder
    private var adviceSection: some View {
        Section {
            LabeledContent("Reminders sent", value: "\(summary.shown)")
                .monospacedDigit()
            LabeledContent("Opened", value: "\(summary.opened)")
                .monospacedDigit()
            if let rate = summary.acceptanceRate {
                LabeledContent("You said you used the card", value: percent(rate))
                    .monospacedDigit()
            } else {
                Text("Nothing answered yet. The question appears on the wallet after a reminder, and ignoring it is a fine thing to do with it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Whether the advice landed").textCase(nil)
        } footer: {
            if summary.acceptanceRate != nil {
                Text("Out of the reminders you answered, not out of all of them.")
            }
        }
    }

    // MARK: - Restraint

    private var quietSection: some View {
        Section {
            LabeledContent("Times it stayed quiet", value: "\(summary.suppressed)")
                .monospacedDigit()
        } header: {
            Text("When it said nothing").textCase(nil)
        } footer: {
            Text("Arrivals where there was nothing worth interrupting you for: the same shop twice in a day, a card with no real lead over the others, or a cap already spent. Counted because staying quiet is half the job.")
        }
    }

    private var nothingYetSection: some View {
        Section {
            Text("Nothing yet. Once a reminder has reached you, what came of it appears here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - The switch

    private var recordingSection: some View {
        Section {
            Toggle("Keep track of this", isOn: Binding(
                get: { impact.isRecording },
                set: { impact.setRecording($0) }
            ))
            if impact.isRecording && summary.hasAnythingToShow {
                Button("Erase this history", role: .destructive) { impact.erase() }
            }
        } footer: {
            Text("Kept on this iPhone and nowhere else. There is no account, nothing is uploaded, and no bank or card account is ever read — the dollar figures are the ones you typed in. Switching this off erases what is here.")
        }
    }

    // MARK: - Numbers as words

    private func dollars(_ cents: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: cents / 100)) ?? String(format: "$%.2f", cents / 100)
    }

    private func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }
}

#Preview {
    NavigationStack {
        ImpactView()
    }
    .environment(ImpactStore.previewStore())
}
