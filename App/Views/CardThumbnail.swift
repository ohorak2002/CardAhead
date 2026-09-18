import SwiftUI
import CardKit

/// Colour, finish and chip at row size. The adjacent row supplies the name.
struct CardThumbnail: View {
    let card: Card
    var photo: Image?
    var width: CGFloat = 62
    var use: ArtUse = .appDisplay

    var body: some View {
        let artwork = CardArtwork(card: card, photo: photo, use: use)
        Group {
            if artwork.isLicensed, let image = artwork.image {
                image.resizable().scaledToFit()
            } else {
                ZStack(alignment: .leading) {
                    if let image = artwork.image {
                        image.resizable().scaledToFill()
                    } else {
                        CardMaterial(art: CardArt.art(for: card.artKey), finish: card.appearance)
                        EMVChip()
                            .frame(width: width * 0.115, height: width * 0.088)
                            .padding(.leading, width * 0.06)
                    }
                }
                .frame(width: width, height: width / 1.586)
                .clipShape(RoundedRectangle(cornerRadius: width * 0.055, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: width * 0.055, style: .continuous)
                        .strokeBorder(.white.opacity(0.3), lineWidth: 0.5)
                }
            }
        }
        .frame(width: width, height: width / 1.586)
        .shadow(color: .black.opacity(0.16), radius: 2, y: 1)
        .accessibilityHidden(true)
    }
}