import SwiftUI
import CardKit

/// *Which card should I pull out?* — answered, on the screen that asks it.
///
/// **Card, reward, reason. In that order, and nothing else above the fold.**
/// The engine knows a great deal more — alternates, caveats, the margin over
/// the next best card, an activation nudge — and every one of those is a
/// reason to hesitate at the till. Somebody standing at a counter needs one
/// card named and one sentence saying why. The rest is a tap away, which is
/// the right distance for it.
///
/// **The card face is the hero and that is the whole design.** These are
/// people's actual cards; a recommendation rendered as a row of text with a
/// small icon is a notification, not an answer. At this size the art is
/// recognisable from across a table, which is what makes "the gold one" a
/// usable instruction.
///
/// Nothing here is asserted. The place, the card and the rate come from
/// `MapPlaceResult`; the reason is the engine's own `headline`. This view
/// formats what it is handed and computes nothing — the moment a view starts
/// deciding which card wins, there are two ranking engines.
struct RecommendationHero: View {

    let card: Card
    /// Loaded by the caller, like every other card face in the app.
    var photo: Image?
    let placeName: String
    let distance: String
    /// "4x points with American Express Gold". Nil when the engine can name a
    /// card but not a rate, which is ordinary.
    let rewardLine: String?
    /// The engine's own sentence. Never rewritten here.
    let reason: String

    /// Opens the map on this place. The label says where it goes.
    var onOpen: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            face
            details
        }
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous)
        )
        // The lifted level, not the resting one. This is the one panel on the
        // screen that is genuinely being held out to you.
        .shadow(
            color: Color.cardWiseNavy.opacity(Metric.liftedShadow.opacity),
            radius: Metric.liftedShadow.radius,
            x: 0,
            y: Metric.liftedShadow.y
        )
        // A short settle on first appearance — the card arriving rather than
        // being already there. Not a bounce: this is a financial
        // recommendation, and spring physics would make it read as a prize.
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 8)
        .onAppear {
            guard !hasAppeared else { return }
            if reduceMotion {
                hasAppeared = true
            } else {
                withAnimation(.easeOut(duration: 0.28)) { hasAppeared = true }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(voiceOverLabel)
        .accessibilityHint("Opens this place on the map")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - The card

    /// Sat on its own ground rather than on the panel, so the art has an edge
    /// even when the card itself is pale — a white card on a white panel is a
    /// floating rectangle of text.
    private var face: some View {
        CardFaceView(card: card, photo: photo)
            .frame(maxWidth: 260)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, Metric.roomy)
            .padding(.horizontal, Metric.regular)
            .background(Color.cardWiseCanvas)
    }

    // MARK: - The words

    private var details: some View {
        VStack(alignment: .leading, spacing: Metric.snug) {
            // The reward is the largest text in the block, because it is the
            // number the decision turns on.
            if let rewardLine {
                Text(rewardLine)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Color.cardWiseBlue)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(card.displayName)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Label {
                Text("\(placeName) · \(distance)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "mappin.and.ellipse")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text(reason)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("See it on the map", action: onOpen)
                .buttonStyle(.cardWiseSecondary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metric.regular)
    }

    /// One sentence rather than four fragments. VoiceOver reads the combined
    /// element, so the order here is the order it is spoken in, and it has to
    /// make sense as speech.
    private var voiceOverLabel: String {
        var parts = [rewardLine ?? card.displayName]
        parts.append("at \(placeName), \(distance) away")
        parts.append(reason)
        return parts.joined(separator: ". ")
    }
}
