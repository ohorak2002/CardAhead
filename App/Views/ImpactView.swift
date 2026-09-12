import SwiftUI
import UIKit
import CardKit

/// Has this app been worth carrying?
///
/// **What this screen will not say.** Not "saved". Nothing was discounted, no
/// price was lowered, and this app has never seen a transaction — every figure
/// here rests on a number somebody typed in and a point valuation they set
/// themselves. The headline is what *choosing differently* is estimated to
/// have earned over the next best card in the same wallet, which is the only
/// part of a reward an app can take any credit for. A card earning 4x would
/// have earned 4x whether or not anybody was told about it; being told is
/// worth the gap, not the total.
///
/// The one number gets the gradient and the big type because it is the only
/// number here anybody came for. Everything under it is supporting evidence
/// and is sized like it.
struct ImpactView: View {

    @Environment(ImpactStore.self) private var impact

    private var summary: ImpactSummary { impact.summary }

    var body: some View {
        ScrollView {
            VStack(spacing: Metric.roomy) {
                if impact.isRecording {
                    hero
                    if summary.hasAnythingToShow {
                        counts
                        if !summary.categoriesByValue.isEmpty { byCategory }
                        quiet
                    } else {
                        nothingYet
                    }
                }
                recordingControls
            }
            .padding(.horizontal, Metric.margin)
            .padding(.top, Metric.regular)
            .padding(.bottom, Metric.loose)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Your impact")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - The one number

    private var hero: some View {
        VStack(alignment: .leading, spacing: Metric.tight) {
            HStack(alignment: .top) {
                Text(dollars(summary.estimatedIncrementalValueCents))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Spacer(minLength: Metric.tight)
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .accessibilityHidden(true)
            }
            Text(heroCaption)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metric.roomy)
        .background(.cardWiseAccentGradient, in: RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous))
        .shadow(color: Color.cardWiseBlue.opacity(0.28), radius: 14, x: 0, y: 6)
        .accessibilityElement(children: .combine)
    }

    private var heroCaption: String {
        guard summary.priced > 0 else {
            return "Estimated extra rewards. Nothing priced yet."
        }
        let purchases = summary.priced == 1 ? "one purchase" : "\(summary.priced) purchases"
        return "Estimated extra rewards, over your next best card, across \(purchases)."
    }

    // MARK: - Supporting evidence

    private var counts: some View {
        HStack(spacing: Metric.snug) {
            StatTile(value: "\(summary.shown)", label: "Reminders")
            StatTile(value: "\(summary.accepted)", label: "You used")
            StatTile(value: "\(summary.priced)", label: "Priced")
        }
    }

    private var byCategory: some View {
        VStack(alignment: .leading, spacing: Metric.snug) {
            SectionHeader("Where it came from")

            VStack(spacing: Metric.snug) {
                ForEach(summary.categoriesByValue, id: \.category) { entry in
                    CategoryValueBar(
                        category: entry.category,
                        cents: entry.cents,
                        fraction: fraction(of: entry.cents)
                    )
                }
            }
            .padding(Metric.regular)
            .cardWisePanel()
        }
    }

    /// Relative to the biggest bar, not to a total — the bars are for
    /// comparing categories with each other, and scaling them against a sum
    /// makes every bar short as soon as somebody logs a fourth one.
    private func fraction(of cents: Double) -> Double {
        let largest = summary.categoriesByValue.map(\.cents).max() ?? 0
        guard largest > 0 else { return 0 }
        return max(0.04, min(1, cents / largest))
    }

    private var quiet: some View {
        VStack(alignment: .leading, spacing: Metric.tight) {
            HStack {
                CategoryIcon(symbolName: "bell.slash.fill", tint: .secondary, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stayed quiet \(summary.suppressed) times")
                        .font(.subheadline.weight(.semibold))
                    Text("Arrivals where nothing was worth interrupting you for.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(Metric.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardWisePanel()
        .accessibilityElement(children: .combine)
    }

    private var nothingYet: some View {
        Text("Nothing yet. Once a reminder has reached you, what came of it appears here — and answering it is entirely optional.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Metric.regular)
            .cardWisePanel()
    }

    // MARK: - The switch

    private var recordingControls: some View {
        VStack(alignment: .leading, spacing: Metric.snug) {
            Toggle("Keep track of this", isOn: Binding(
                get: { impact.isRecording },
                set: { impact.setRecording($0) }
            ))
            .font(.subheadline.weight(.medium))

            Text("Kept on this iPhone and nowhere else. There is no account, nothing is uploaded, and no bank or card account is ever read — the dollar figures are the ones you typed in. Switching this off erases what is here.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if impact.isRecording && summary.hasAnythingToShow {
                Button("Erase this history", role: .destructive) { impact.erase() }
                    .font(.subheadline)
                    .padding(.top, 2)
            }
        }
        .padding(Metric.regular)
        .cardWisePanel()
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
}

/// One category's share, as a bar. Its own colour, so the same green means
/// groceries here as it does on the Benefits grid.
private struct CategoryValueBar: View {
    let category: SpendingCategory
    let cents: Double
    let fraction: Double

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: Metric.tight) {
                CategoryIcon(symbolName: category.symbolName, tint: category.tint, size: 28)
                Text(category.displayName)
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer(minLength: Metric.tight)
                Text(amount)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(category.tint.opacity(0.14))
                    Capsule()
                        .fill(category.tint)
                        .frame(width: max(6, proxy.size.width * fraction))
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(category.displayName), \(amount)")
    }

    private var amount: String {
        String(format: "$%.2f", cents / 100)
    }
}

#Preview {
    NavigationStack {
        ImpactView()
    }
    .environment(ImpactStore.previewStore())
}
