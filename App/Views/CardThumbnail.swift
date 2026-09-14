import SwiftUI
import CardKit

/// A card at list-row size.
///
/// Not a shrunken `CardFaceView`: that one is drawn with absolute type sizes so
/// a real card reads like a real card, and scaling it down to 60pt turns the
/// issuer's name into a smear. A row needs the thing you recognise out of the
/// corner of your eye — the colour, the finish, and the chip — and nothing else.
///
/// It goes through `CardArtSource` like every other drawing of a card, so a
/// licensed asset appears here the day one exists and never a day before.
struct CardThumbnail: View {
    let card: Card
    var photo: Image?
    var width: CGFloat = 62

    private var art: CardArt { CardArt.art(for: card.artKey) }

    private var licensedArt: Image? {
        guard case .licensed(let asset) = CardArtSource.resolve(for: card) else { return nil }
        return Image(asset.imageName)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let licensedArt {
                licensedArt.resizable().scaledToFill()
            } else if let photo {
                photo.resizable().scaledToFill()
            } else {
                art.gradient
                // The material, but deliberately **not** the palette's surface
                // pattern. Those are spaced for a card 350pt wide; at 62pt the
                // same spacing is four lines across the whole thumbnail, which
                // reads as stripes rather than as texture. Same reasoning as
                // the type sizes above.
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0), location: max(0, 0.47 - card.appearance.sheenSpread)),
                        .init(color: .white.opacity(card.appearance.sheenOpacity), location: 0.47),
                        .init(color: .white.opacity(0), location: min(1, 0.47 + card.appearance.sheenSpread))
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color(red: 0.85, green: 0.74, blue: 0.42))
                    .frame(width: width * 0.17, height: width * 0.13)
                    .padding(.leading, width * 0.12)
                    .padding(.bottom, width * 0.16)
            }
        }
        .frame(width: width, height: (width / 1.586).rounded())
        .clipShape(RoundedRectangle(cornerRadius: width * 0.1, style: .continuous))
        .overlay {
            // Top-lit, like the full-size face: bright along the top edge,
            // dark along the bottom. A flat border all the way round is the
            // thing that makes a small card look like a swatch.
            RoundedRectangle(cornerRadius: width * 0.1, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.34), .white.opacity(0.06), .black.opacity(0.18)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        }
        .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
        .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 12) {
        CardThumbnail(card: CardCatalog.amexGold)
        CardThumbnail(card: CardCatalog.chaseSapphirePreferred)
        CardThumbnail(card: CardCatalog.discoverIt)
    }
    .padding()
}
