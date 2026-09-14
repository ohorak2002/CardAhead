import SwiftUI
import CardKit

/// The card itself, drawn to look like a card rather than a coloured tile.
///
/// Three things do most of that work: the real ISO/IEC 7810 ID-1 proportion
/// (85.60 × 53.98 mm, so 1.586:1), a material finish, and the two components
/// every modern card carries — the EMV chip and the contactless mark. Those are
/// industry-standard parts, not anyone's branding, so they can be drawn.
///
/// What is deliberately *not* here is the issuer's own artwork. Apple Wallet
/// shows the real Amex face because Amex sends it during provisioning; we have
/// no such relationship, and copying the art would be trademark infringement.
/// The exact-match route is `photoFilename` — a photo of the user's own card.
///
/// The top strip is the only part visible while stacked, so it carries the
/// bank and the card name, which is exactly why issuers top-align their
/// branding in the first place.
struct CardFaceView: View {
    let card: Card
    var highlight: String?
    /// Set when this is the card being recommended right now.
    var isRecommended: Bool = false
    /// Loaded by the caller; nil when the user never added a photo.
    var photo: Image?

    @ScaledMetric(relativeTo: .title3) private var cornerRadius: CGFloat = 15

    private var art: CardArt { CardArt.art(for: card.artKey) }
    private var finish: CardFinish { card.appearance }

    /// Resolved once. Three separate calls would be three chances for the
    /// face, the caption and the VoiceOver label to disagree about which of
    /// the three sources is actually on screen.
    private var source: CardArtSource { CardArtSource.resolve(for: card) }

    /// Only ever non-nil for artwork we hold a licence for. `CardArtLibrary`
    /// does the refusing, so nothing here has to remember to check.
    private var licensedArt: Image? {
        guard case .licensed(let asset) = source else { return nil }
        return Image(asset.imageName)
    }

    /// True when a real photograph is behind the text, licensed or the user's.
    private var hasImageBehindText: Bool { licensedArt != nil || photo != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandingStrip
            earnStrip
            Spacer(minLength: 8)
            chipStrip
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .aspectRatio(1.586, contentMode: .fit)
        .background(plate)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - The plate

    @ViewBuilder
    private var plate: some View {
        ZStack {
            if let licensed = licensedArt {
                licensed
                    .resizable()
                    .scaledToFill()
            } else if let photo {
                photo
                    .resizable()
                    .scaledToFill()
            } else {
                art.gradient
                if finish.isBrushed { brushedLines }
            }

            // Vibrancy: text needs its own ground, or it stops being legible
            // the moment someone drops in a photo of a pale card.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(hasImageBehindText ? 0.58 : 0.18), location: 0),
                    .init(color: .black.opacity(hasImageBehindText ? 0.22 : 0.02), location: 0.34),
                    .init(color: .black.opacity(hasImageBehindText ? 0.40 : 0.10), location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )

            sheen
        }
    }

    /// Where the light catches the card.
    private var sheen: some View {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(0), location: 0.30),
                .init(color: .white.opacity(finish.sheenOpacity), location: 0.47),
                .init(color: .white.opacity(0), location: 0.64)
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    /// Fine parallel lines — the reason a metal card reads as metal.
    private var brushedLines: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                for x in stride(from: 0.0, to: size.width, by: 3) {
                    let rect = CGRect(x: x, y: 0, width: 1, height: size.height)
                    context.fill(Path(rect), with: .color(.white.opacity(0.07)))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    // MARK: - Content

    private var brandingStrip: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(card.issuer)
                .font(.system(size: 17, weight: .bold))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(card.name)
                .font(.system(size: 12.5, weight: .semibold))
                .opacity(0.92)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
    }

    @ViewBuilder
    private var earnStrip: some View {
        HStack(spacing: 9) {
            if let highlight {
                Text(highlight)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(hasImageBehindText ? .white : art.accent)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
            }
            if isRecommended {
                Text("Use this")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
    }

    private var chipStrip: some View {
        HStack(alignment: .bottom, spacing: 10) {
            EMVChip()
                .frame(width: 38, height: 29)
            ContactlessMark()
                .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 1.9, lineCap: .round))
                .frame(width: 17, height: 20)
            Spacer(minLength: 0)
            if card.isPinned {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.85))
                    .accessibilityLabel("Preferred for ties")
            }
        }
    }

    /// VoiceOver is told which of the three faces this is, because the
    /// difference between a photograph of somebody's own card and a drawing of
    /// it is the entire subject here and is invisible to a screen reader
    /// otherwise. A photo that failed to load is described as the drawing it
    /// actually is, not as the photo it was meant to be.
    private var accessibilityText: String {
        var described = source
        switch source {
        // A photo whose file has gone is described as the drawing it actually
        // is, not the photo it was meant to be.
        case .userPhoto where photo == nil: described = .drawn
        // And a photo handed in before it has been saved onto the card — the
        // preview on the "use a photo" screen — is described as the photo it
        // visibly already is.
        case .drawn where photo != nil: described = .userPhoto("")
        default: break
        }
        var parts = [described.accessibilityDescription(for: card)]
        if let highlight { parts.append(highlight) }
        if isRecommended { parts.append("Recommended here") }
        if card.isPinned { parts.append("Preferred for ties") }
        return parts.joined(separator: ", ")
    }
}

/// The gold contact plate. Every card has one and no wallet mockup draws it.
private struct EMVChip: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.94, green: 0.89, blue: 0.71),
                        Color(red: 0.79, green: 0.66, blue: 0.31),
                        Color(red: 0.96, green: 0.91, blue: 0.77),
                        Color(red: 0.62, green: 0.49, blue: 0.20)
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .overlay {
                GeometryReader { proxy in
                    let w = proxy.size.width, h = proxy.size.height
                    Path { path in
                        // the contact pad, and the traces running out of it
                        path.addRoundedRect(
                            in: CGRect(x: w * 0.29, y: h * 0.14, width: w * 0.42, height: h * 0.72),
                            cornerSize: CGSize(width: 2, height: 2)
                        )
                        path.move(to: CGPoint(x: 0, y: h * 0.33))
                        path.addLine(to: CGPoint(x: w, y: h * 0.33))
                        path.move(to: CGPoint(x: 0, y: h * 0.67))
                        path.addLine(to: CGPoint(x: w, y: h * 0.67))
                    }
                    .stroke(.black.opacity(0.3), lineWidth: 1)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(.black.opacity(0.22), lineWidth: 1)
            }
    }
}

/// The four arcs. A standard payment indicator, not a brand mark.
private struct ContactlessMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centre = CGPoint(x: rect.minX, y: rect.midY)
        for step in 1...3 {
            let radius = rect.width * (0.32 * Double(step))
            path.addArc(
                center: centre,
                radius: radius,
                startAngle: .degrees(-52),
                endAngle: .degrees(52),
                clockwise: false
            )
        }
        return path
    }
}

#Preview {
    VStack(spacing: 16) {
        CardFaceView(card: CardCatalog.amexGold, highlight: "4x on restaurants", isRecommended: true)
        CardFaceView(card: CardCatalog.chaseFreedomFlex, highlight: "Switch on 5% for groceries")
    }
    .padding()
}
