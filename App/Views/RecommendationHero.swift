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
    /// What kind of place it is — "Steakhouse". Sits beside the distance on
    /// the identity line, and is dropped rather than faked when unknown.
    var placeSubtitle: String?
    /// The photograph of the *place* (not the card). Small and contextual
    /// here: enough to recognise where this is about, not a hero image.
    var placePhoto: PlacePhoto?
    var placeSymbol: String = "mappin.and.ellipse"
    var placeTint: Color = .cardWiseBlue
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
            place
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

    // MARK: - Where

    /// **The place goes first now, and it did not before.**
    ///
    /// The old order was card, reward, place, reason — which reads as "here is
    /// a card, and by the way it is about somewhere". A recommendation is
    /// about a *place*: the first question is "where do you mean?", and only
    /// once that is settled does "which card?" mean anything. Somebody who
    /// does not recognise the place has no use for the answer at all.
    ///
    /// Small, though. This is context, not the subject — a 56-point square
    /// and two lines, which is about as much room as recognising a shop needs.
    private var place: some View {
        HStack(spacing: Metric.snug) {
            PlacePhotoView(
                photo: placePhoto,
                symbolName: placeSymbol,
                tint: placeTint,
                use: .row,
                cornerRadius: 14
            )
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 2) {
                Text(placeName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitleLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metric.regular)
        .padding(.top, Metric.regular)
        .padding(.bottom, Metric.snug)
    }

    private var subtitleLine: String {
        guard let placeSubtitle, !placeSubtitle.isEmpty else { return distance }
        return "\(placeSubtitle) · \(distance)"
    }

    // MARK: - The card

    /// **Smaller than it was, and no longer on a ground of its own.**
    ///
    /// Two things the screenshots settled. At 260 points wide with 24 points
    /// of air above and below, the face alone was 450 points of an 874-point
    /// screen, so the wallet — the thing directly under it — never appeared
    /// above the fold on any phone. The art still has to be recognisable from
    /// across a table, which is what makes "the gold one" a usable
    /// instruction; 210 points is still that.
    ///
    /// And it used to sit on a `cardWiseCanvas` band, on the argument that a
    /// pale card on a white panel would have no edge. On screen that read as
    /// exactly what it was — **a rounded rectangle inside a rounded
    /// rectangle**, which is the tell this redesign is supposed to be removing
    /// rather than adding. The argument was also wrong on its own terms:
    /// `CardFaceView` draws its own shadow and its own hairline border, which
    /// is why the wallet has always shown these straight onto the page and
    /// never needed a ground. Same treatment here.
    private var face: some View {
        CardFaceView(card: card, photo: photo)
            .frame(maxWidth: 210)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, Metric.regular)
            .padding(.horizontal, Metric.regular)
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

            // **The place used to be repeated here** — name and distance, in
            // grey, under the reward. It is the first thing on the panel now,
            // with a photograph beside it, so saying it again was the same
            // fact twice on one card.

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
        // Spoken in the order the panel is now read in: where, then what to
        // pay with, then why.
        var parts = ["\(placeName), \(distance) away"]
        parts.append(rewardLine ?? card.displayName)
        parts.append(reason)
        return parts.joined(separator: ". ")
    }
}
