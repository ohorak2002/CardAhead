import SwiftUI
import CardKit

// MARK: - A rule that is actually visible

/// A hairline, drawn from the palette rather than by `Divider`.
///
/// **`Divider` is a hierarchical style and vanished on the map sheet** — the
/// same way `.secondary` text did, and for the same reason. `cardWiseHairline`
/// is an asset-catalog colour with a light and a dark value, which resolves to
/// a real colour on any ground. See `CardWiseBottomSheet`'s note.
struct Hairline: View {
    var inset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Color.cardWiseHairline)
            .frame(height: 1)
            .padding(.leading, inset)
            .accessibilityHidden(true)
    }
}

// MARK: - A row

/// One place in a list: a photograph of it, what it is, how far, and which
/// card wins there.
///
/// **This used to be a rounded card and is deliberately not one any more.**
/// Twenty rows, each a white panel with a soft shadow, reads as twenty
/// competing objects — and the thing that was supposed to stand out, the
/// reward line, was the fourth-loudest element in its own row. A photograph
/// with type beside it needs no container: the picture *is* the edge. What
/// separates one row from the next is a hairline and ten points of air, which
/// is what separates rows in every list Apple ships.
///
/// The photograph is doing a job no glyph could. A blue fork means
/// "restaurant"; a picture of the place means "the one on the corner", and
/// recognising where you are is the entire premise of this screen.
struct MerchantRow: View {

    let result: MapPlaceResult
    var isWatched: Bool = false
    /// Drawn under every row but the last. The list owns that decision, since
    /// only the list knows which row is last.
    var showsSeparator: Bool = true

    /// **68, down from 76.** At 76 with 12 points of air above and below, a
    /// row was 100 points and the sheet showed three of them at its resting
    /// height — a list you cannot see enough of to scan. 88 shows four and a
    /// half, and the thumbnail is still comfortably bigger than the 44-point
    /// minimum it also has to clear as a tap target.
    private let photoSize: CGFloat = 68

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Metric.snug) {
                PlacePhotoView(place: result.place, use: .row)
                    .frame(width: photoSize, height: photoSize)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(result.place.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                        if isWatched { WatchingMark() }
                    }

                    PlaceFactsLine(result: result)

                    // **The line the row exists for, and the only coloured
                    // text in it.** Everything above is grey or black on
                    // purpose, so this reads first even though it is last.
                    Text(result.rewardLine ?? "No card of yours earns extra here")
                        .font(.caption.weight(result.rewardLine == nil ? .regular : .semibold))
                        .foregroundStyle(result.rewardLine == nil ? Color.secondary : Color.cardWiseBlue)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.secondary.opacity(0.5))
            }
            .padding(.vertical, 10)

            if showsSeparator {
                // Inset to the text, not to the photo: a full-bleed rule under
                // a picture cuts the row in half rather than separating it
                // from the next one.
                Hairline(inset: photoSize + Metric.snug)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// "Steakhouse · 0.3 mi · ★ 4.6 · Open". The facts nobody reads one at a
/// time, so they live on one quiet line.
///
/// Each part is dropped rather than faked when it is unknown, and the
/// separators go with it — a row reading "· 0.3 mi · ·" is what happens when
/// a fixed format meets a place Google knows little about.
///
/// **Every colour here is an explicit `Color`.** `.secondary` is a
/// hierarchical style, and this line is drawn on the map's sheet, where a
/// hierarchical style rendered as nothing at all. See `CardWiseBottomSheet`.
struct PlaceFactsLine: View {
    let result: MapPlaceResult
    var showsOpenState = false

    var body: some View {
        HStack(spacing: 5) {
            Text(result.place.subtitle)
                .lineLimit(1)
            Text("·")
            Text(result.distanceText)
                .monospacedDigit()
            if let rating = result.place.rating {
                Text("·")
                HStack(spacing: 2) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                    Text(String(format: "%.1f", rating))
                        .monospacedDigit()
                }
            }
            if showsOpenState, let isOpen = result.place.isOpenNow {
                Text("·")
                Text(isOpen ? "Open" : "Closed")
                    // Explicit `Color` on both branches — `.secondary`
                    // resolves against `ShapeStyle` and would not unify.
                    // This repo has hit that twice.
                    .foregroundStyle(isOpen ? Color.cardWiseSuccess : Color.secondary)
                    .fontWeight(.medium)
            }
        }
        .font(.caption)
        .foregroundStyle(Color.secondary)
        .lineLimit(1)
    }
}

// MARK: - The card

/// A place, shown properly: what it is, and which card to reach for.
///
/// The order is the argument. **Place, then card, then reward, then why** —
/// somebody who has just tapped a pin is asking "what is this?" first and
/// "what should I pay with?" a half-second later, and an interface that
/// answers in the other order makes them hunt for the name.
///
/// **Each fact appears once.** The reward reads "4x points on dining" under a
/// card named once above it, not "Use Amex Gold for 4x points" under a
/// heading that already said Amex Gold. The last line is the one place a
/// sentence earns its space, so it carries something the lines above do not:
/// what the next best card in the wallet would have paid.
struct MerchantPlaceCard: View {

    let result: MapPlaceResult
    var isWatched: Bool = false
    var onOpen: (() -> Void)?
    var onDismiss: (() -> Void)?

    @Environment(\.openURL) private var openURL

    /// Whether this place has a photograph at all — known synchronously, and
    /// it changes the whole top of the card.
    private var hasPhoto: Bool { result.place.photo != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasPhoto { photo }
            identity
            if result.recommendation != nil {
                Hairline().padding(.vertical, Metric.regular)
                recommendation
            } else {
                Hairline().padding(.vertical, Metric.regular)
                noRecommendation
            }
            actions
        }
        .padding(.horizontal, Metric.margin)
    }

    // MARK: Photo

    /// **Drawn only when the place actually has one.**
    ///
    /// The first version reserved 150 points for the picture whatever
    /// happened, and the screenshots showed what that costs: a card whose top
    /// third was an empty blue rectangle with a small bed in the middle of it,
    /// on a place that simply has no photograph — which is most of them. A
    /// space held open for something that is never coming is the blank
    /// placeholder every design guide tells you not to ship.
    ///
    /// So a place with no photograph gets its category mark beside its name
    /// instead, and the card starts on the thing it is about.
    private var photo: some View {
        PlacePhotoView(place: result.place, use: .card, cornerRadius: Metric.tileRadius)
            .frame(height: 150)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topTrailing) {
                if onDismiss != nil { closeButton }
            }
            .padding(.bottom, Metric.regular)
    }

    private var closeButton: some View {
        Button { onDismiss?() } label: {
            Image(systemName: "xmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.primary)
                .frame(width: 30, height: 30)
                .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .padding(Metric.tight)
        .accessibilityLabel("Close")
    }

    // MARK: Who and where

    private var identity: some View {
        HStack(alignment: .top, spacing: Metric.snug) {
            if !hasPhoto {
                CategoryIcon(
                    symbolName: result.place.mapCategory.symbolName,
                    tint: result.place.mapCategory.listTint,
                    size: 46
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(result.place.name)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(2)
                    if isWatched { WatchingMark() }
                }
                PlaceFactsLine(result: result, showsOpenState: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { onOpen?() }

            // With no photograph there is nowhere for the close button to sit
            // over an image, so it joins the title row.
            if !hasPhoto, onDismiss != nil {
                closeButton
                    .padding(.top, -Metric.tight)
                    .padding(.trailing, -Metric.tight)
            }
        }
    }

    // MARK: The answer

    private var recommendation: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CardWise recommendation")
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .kerning(0.6)
                .foregroundStyle(Color.secondary)

            if let best = result.recommendation?.best {
                Text("Use \(best.card.displayName)")
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                    .lineLimit(2)

                Text(best.reason)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.cardWiseBlue)
                    .lineLimit(2)
            }

            // The one line here that says something the others do not — see
            // `Recommendation.runnerUpLine`. Nil for a one-card wallet and for
            // a tie, and nothing is drawn in its place.
            if let why = result.recommendation?.runnerUpLine {
                Text(why)
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Said plainly rather than hidden. A place where no card of yours does
    /// anything special is a real answer, and the most common one.
    private var noRecommendation: some View {
        Text(result.place.spendingCategory == nil
             ? "CardWise cannot tell what this place codes as, so it will not guess a card."
             : "No card in your wallet earns extra here. Any of them pays its usual rate.")
            .font(.footnote)
            .foregroundStyle(Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: Metric.snug) {
            Button {
                openDirections()
            } label: {
                Label("Directions", systemImage: "arrow.triangle.turn.up.right.circle.fill")
            }
            .buttonStyle(CardWiseSecondaryButtonStyle())

            if let onOpen {
                Button("Details", action: onOpen)
                    .buttonStyle(CardWiseSecondaryButtonStyle())
            }
        }
        .padding(.top, Metric.regular)
    }

    /// Hands the place to Apple Maps rather than drawing a route.
    ///
    /// Turn-by-turn is a whole application, the phone already has two of them,
    /// and the one the user prefers is the one that opens. The name goes in
    /// the query so Maps shows "Peachtree Chophouse" rather than a pin at a
    /// pair of coordinates.
    private func openDirections() {
        var components = URLComponents(string: "http://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(
                name: "daddr",
                value: "\(result.place.coordinate.latitude),\(result.place.coordinate.longitude)"
            ),
            URLQueryItem(name: "q", value: result.place.name)
        ]
        guard let url = components?.url else { return }
        openURL(url)
    }
}
