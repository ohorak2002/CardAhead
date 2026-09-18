import SwiftUI
import CardKit

/// A named winner first, then its nearby place, artwork and supporting evidence.
/// Ranking and rate selection remain the caller's engine-derived values.
struct RecommendationHero: View {
    let card: Card
    var photo: Image?
    let placeName: String
    var placeSubtitle: String?
    let distance: String
    let rewardLine: String?
    let reason: String
    var onOpen: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Metric.regular) {
            VStack(alignment: .leading, spacing: Metric.tight) {
                Label("Use this card", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.cardWiseActionInk)
                Text(card.displayName)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("At \(placeName)")
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitleLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            // Large type spends its room on the answer. The image remains
            // recognisable, while its tiny printed words are not relied upon.
            CardFaceView(card: card, photo: photo, use: .appDisplay)
                .frame(maxWidth: typeSize.isAccessibilitySize ? 210 : 260)
                .frame(maxWidth: .infinity)

            if let rewardLine {
                Text(rewardLine)
                    .font(.headline)
                    .foregroundStyle(Color.cardWiseActionInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(reason)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Open nearby map", action: onOpen)
                .buttonStyle(.cardWiseSecondary)
        }
        .padding(Metric.regular)
        .cardWisePanel()
        // Content is a container, never a pretend button surrounding a button.
        .accessibilityElement(children: .contain)
    }

    private var subtitleLine: String {
        guard let placeSubtitle, !placeSubtitle.isEmpty else { return "\(distance) away" }
        return "\(placeSubtitle), \(distance) away"
    }
}