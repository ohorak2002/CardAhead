import SwiftUI
import UIKit
import CardKit

/// One load and one source description for both sizes of card artwork.
struct CardArtwork {
    let source: CardArtSource
    let image: Image?

    init(card: Card, photo: Image?, use: ArtUse) {
        let selected = CardArtSource.resolve(for: card, use: use)
        var licensed: UIImage?
        if case .licensed(let asset) = selected {
            licensed = UIImage(named: asset.imageName)
        }
        source = selected.availableForDisplay(
            licensedImageAvailable: licensed != nil,
            photoAvailable: photo != nil
        )
        switch source {
        case .licensed: image = licensed.map { Image(uiImage: $0) }
        case .userPhoto: image = photo
        case .drawn: image = nil
        }
    }

    var isLicensed: Bool {
        if case .licensed = source { return true }
        return false
    }
}

/// Original static materials, shared by the full face and the thumbnail.
/// All textures are procedural and independent of issuer identity.
struct CardMaterial: View {
    let art: CardArt
    let finish: CardFinish

    var body: some View {
        ZStack {
            art.gradient
            LinearGradient(
                colors: [.white.opacity(finish.sheenOpacity * 0.6), .clear, .black.opacity(0.22)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Canvas { context, size in
                if finish.isBrushed {
                    for y in stride(from: 0.0, to: size.height, by: 2) {
                        let line = CGRect(x: 0, y: y, width: size.width, height: 0.5)
                        context.fill(Path(line), with: .color(.white.opacity(0.065)))
                    }
                } else {
                    // A fixed pattern avoids redraw shimmer and random identity.
                    for y in stride(from: 0.0, to: size.height, by: 5) {
                        for x in stride(from: 0.0, to: size.width, by: 5) {
                            let dot = CGRect(x: x + (Int(y) % 2 == 0 ? 0 : 2), y: y, width: 0.7, height: 0.7)
                            context.fill(Path(ellipseIn: dot), with: .color(.white.opacity(finish == .frosted ? 0.12 : 0.045)))
                        }
                    }
                }
            }
            if finish == .glossy || finish == .metal {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.28),
                        .init(color: .white.opacity(finish.sheenOpacity * 0.45), location: 0.45),
                        .init(color: .clear, location: 0.62)
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            }
            // A consistent ink ground keeps light finishes readable.
            Color.black.opacity(0.42)
        }
        .accessibilityHidden(true)
    }
}
