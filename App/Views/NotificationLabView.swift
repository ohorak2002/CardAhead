import SwiftUI
import CardKit

/// Every decision the notification policy has made, with its arithmetic, and
/// the seventeen category badges side by side.
///
/// **This is the screen that makes the weights tunable.** A score is a number
/// nobody can argue with until they can see what it is made of; "74" says
/// nothing, and "+38 card advantage, +22 likely value, +7 two cards here, +17
/// sure where you are, −10 already sent one today" is a thing somebody can
/// look at and say *that one is wrong*. Without it, tuning this policy would
/// mean walking around a city and guessing.
///
/// **And the badges are here because CI cannot photograph a notification.**
/// A simulator screenshot captures screens; the coloured chip on a reminder is
/// drawn by `ReminderBadge` into a PNG that only iOS ever renders. Putting all
/// seventeen on a real screen is the one way their colour and glyph can be
/// checked without a phone — this screen is in the screenshot list for exactly
/// that reason.
///
/// Debug builds only. It is a workbench, not a feature: it shows raw scores,
/// merchant ids and suppression reasons in the app's internal vocabulary, none
/// of which belongs in a shipping build.
struct NotificationLabView: View {

    @Environment(NotificationPolicyStore.self) private var notifications

    var body: some View {
        List {
            todaySection
            decisionsSection
            badgeSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Notification lab")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Where the budget stands

    private var todaySection: some View {
        let thresholds = notifications.policy.thresholds
        let spent = notifications.history.sentCount(on: Date())
        return Section {
            LabeledContent("Intensity", value: notifications.policy.intensity.displayName)
            LabeledContent("Sent today", value: "\(spent) of \(thresholds.dailyBudget)")
            LabeledContent("Score needed", value: String(format: "%.0f", thresholds.minimumScore))
            LabeledContent(
                "Same shop",
                value: "\(Int(thresholds.merchantCooldownHours))h"
            )
            LabeledContent(
                "Same category",
                value: "\(Int(thresholds.categoryCooldownHours))h"
            )
            LabeledContent(
                "Beats a full day",
                value: String(format: "$%.2f", thresholds.overrideValueCents / 100)
            )
        } header: {
            Text("The policy in force").textCase(nil)
        }
    }

    // MARK: - What it decided

    @ViewBuilder
    private var decisionsSection: some View {
        Section {
            if notifications.history.records.isEmpty {
                Text("Nothing decided yet. A decision is recorded every time a geofence you are inside holds for its four minutes — sent or not.")
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            } else {
                ForEach(notifications.history.newestFirst) { record in
                    DecisionRow(record: record)
                }
            }
        } header: {
            Text("Recent decisions").textCase(nil)
        } footer: {
            Text("Kept for four days, then dropped. Suppressions are here too — a silence with no trace is indistinguishable from a bug.")
        }
    }

    // MARK: - The badges

    private var badgeSection: some View {
        Section {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 64), spacing: Metric.gap)],
                spacing: Metric.gap
            ) {
                ForEach(SpendingCategory.allCases, id: \.self) { category in
                    VStack(spacing: 4) {
                        BadgePreview(category: category)
                        Text(category.emoji)
                            .font(.caption)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(category.placePhrase)
                }
            }
            .padding(.vertical, Metric.gap)
        } header: {
            Text("Notification badges").textCase(nil)
        } footer: {
            Text("The chip drawn on the trailing edge of a reminder, and the emoji that leads its title. A real notification cannot be screenshotted, so this is where these get looked at.")
        }
    }
}

/// One decision, openable.
private struct DecisionRow: View {

    let record: NotificationRecord
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: Metric.gap) {
                Image(systemName: record.wasSent ? "bell.badge.fill" : "bell.slash")
                    .foregroundStyle(record.wasSent ? Color.cardWiseSuccess : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.merchantName ?? record.category.placePhrase)
                        .font(.subheadline.weight(.medium))
                    Text(verdict)
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Text(String(format: "%.0f", record.score))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Color.secondary)
            }

            if let feedback = record.feedback {
                Label(feedback.displayName, systemImage: "hand.tap")
                    .font(.caption)
                    .foregroundStyle(Color.cardWiseBlue)
            }

            Text(record.date.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .foregroundStyle(Color.secondary)
        }
        .padding(.vertical, 2)
    }

    private var verdict: String {
        guard let suppression = record.suppression else {
            return "Sent · \(record.band.displayName.lowercased()) · \(record.cardName ?? "a card")"
        }
        return suppression.displayName
    }
}

/// The same drawing `ReminderBadge` puts on a notification, on a screen where
/// it can be photographed.
///
/// Drawn in SwiftUI rather than by calling `ReminderBadge` and showing the
/// PNG, because the PNG is written to a temporary file that iOS immediately
/// takes ownership of. The two must be kept in step by hand: the same
/// `pinTint`, the same symbol, the same corner proportion.
private struct BadgePreview: View {

    let category: SpendingCategory

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(category.pinTint)
            .frame(width: 50, height: 50)
            .overlay {
                Image(systemName: category.symbolName)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}
