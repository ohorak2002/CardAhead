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
                // Only in a build that can actually share. Without a service
                // this screen is a disabled switch and an account form that
                // cannot submit — a dead end for a user, and the first thing
                // App Review flags as an unfinished feature.
                if sharingOffered {
                    NavigationLink("Impact sharing & account") { ImpactSharingView() }
                }
                if !impact.receivedRewards.isEmpty {
                    Text("Reported received: " + CardAheadFormat.money(impact.receivedRewards.reduce(Decimal.zero) { $0 + $1.receivedDollars }))
                    Text("User-reported rewards and credits; not independently verified.").font(.caption)
                }
                recordingControls
            }
            .padding(.horizontal, Metric.margin)
            .padding(.top, Metric.regular)
            // Clear of the floating tab bar, which draws over the end of a
            // scroll view rather than shortening it.
            .padding(.bottom, 90)
        }
        .background(InterfacePalette.page)
        .navigationTitle("CardAhead impact")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - The one number

    private var hero: some View {
        VStack(alignment: .leading, spacing: Metric.tight) {
            HStack(alignment: .top) {
                Text(summary.knownBaselineCount == 0 ? "Unknown" : dollars(summary.estimatedIncrementalValueCents))
                    .font(.system(.largeTitle).weight(.bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Spacer(minLength: Metric.tight)
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: Metric.minimumTarget, height: Metric.minimumTarget)
                    .background(.white.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)
            }
            Text(heroCaption)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metric.roomy)
        .background(.cardAheadAccentGradient, in: RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metric.cardRadius)
                .strokeBorder(.white.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: Color.cardAheadBlue.opacity(0.16), radius: 14, x: 0, y: 6)
        .accessibilityElement(children: .combine)
    }

    private var heroCaption: String {
        guard summary.priced > 0 else {
            return "Estimated extra rewards. Nothing priced yet."
        }
        guard summary.knownBaselineCount > 0 else { return "No comparison baseline. Total estimated rewards are separate from additional value." }
        let purchases = summary.knownBaselineCount == 1 ? "one purchase" : "\(summary.knownBaselineCount) purchases with a known baseline"
        return "Estimated extra rewards, over your next best card, across \(purchases)."
    }

    // MARK: - Supporting evidence

    /// **This was three tiles reading "4 Reminders", "4 You used", "4
    /// Priced" and it had to go.** Three rounded rectangles of numbers is the
    /// visual grammar of an analytics dashboard, which is the one thing this
    /// screen must not be — and "Priced" is engine vocabulary that had leaked
    /// onto a consumer screen. Worst of all, the hero directly above already
    /// ends "...across 4 purchases", so a third of it was a restatement.
    ///
    /// The same three facts, as one sentence somebody can read.
    private var counts: some View {
        Text(countsSentence)
            .font(.subheadline)
            .foregroundStyle(Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var countsSentence: String {
        let shown = summary.shown
        let used = summary.accepted
        guard shown > 0 else { return "No reminder has reached you yet." }

        let reminders = shown == 1 ? "1 reminder" : "\(shown) reminders"
        let opener = used == shown
            ? "\(reminders) reached you, and you used every one."
            : "\(reminders) reached you. You used \(used)."

        // Only mentioned when it differs, because "and 4 of those 4 have a
        // number on them" is a sentence about bookkeeping rather than money.
        guard summary.priced < used else { return opener }
        return opener + " \(summary.priced) of those has a spend on record."
    }

    private var byCategory: some View {
        VStack(alignment: .leading, spacing: Metric.snug) {
            SectionHeader("Where it came from")

            // **No bars, and no panel around them.** A ranked list of three
            // amounts does not need a chart to be read — the order already
            // says which is biggest — and a bar chart inside a rounded card
            // is exactly the dashboard this screen is trying not to be. Rows
            // separated by a hairline, like everywhere else in the app now.
            VStack(spacing: 0) {
                let entries = summary.categoriesByValue
                ForEach(Array(entries.enumerated()), id: \.element.category) { index, entry in
                    CategoryValueRow(category: entry.category, cents: entry.cents)
                    if index < entries.count - 1 { Hairline(inset: 28 + Metric.tight) }
                }
            }
        }
    }

    // The bar-width helper that used to live here went with the bars. It
    // scaled each category against the largest rather than against a total,
    // which was the right rule for a chart — and the chart itself was the
    // thing that did not belong on this screen.

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
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var nothingYet: some View {
        Text("Nothing yet. Once a reminder has reached you, what came of it appears here — and answering it is entirely optional.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Metric.regular)
            .cardAheadPanel()
    }

    /// Whether this build can share at all. See the link in `body`.
    private var sharingOffered: Bool {
        ImpactCloudStore.shared.configured || ImpactCloudStore.shared.signedIn
    }

    // MARK: - The switch

    private var recordingControls: some View {
        VStack(alignment: .leading, spacing: Metric.snug) {
            Toggle("Keep track of this", isOn: Binding(
                get: { impact.isRecording },
                set: { impact.setRecording($0) }
            ))
            .font(.subheadline.weight(.medium))

            Text(sharingOffered
                 ? "Local tracking works without sharing. Optional Impact sharing requires separate consent under Impact sharing & account. No bank account is read; amounts are your reports. Switching local tracking off erases local Impact and stops new sharing. Previously shared records remain until deleted through Impact sharing."
                 : "Kept only on this iPhone. No bank account is read; amounts are your reports. Switching this off erases it.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if impact.isRecording && summary.hasAnythingToShow {
                Button("Erase this history", role: .destructive) { impact.erase() }
                    .font(.subheadline)
                    .padding(.top, 2)
            }
        }
        .padding(Metric.regular)
        .cardAheadPanel()
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
private struct CategoryValueRow: View {
    let category: SpendingCategory
    let cents: Double

    var body: some View {
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
        .padding(.vertical, 10)
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
