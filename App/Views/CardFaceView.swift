import SwiftUI
import CardKit

/// Physical artwork scales as a unit. Hosts provide scalable labels outside
/// the face; VoiceOver receives the complete identity and resolved source.
struct CardFaceView: View {
    let card: Card
    var highlight: String?
    var isRecommended = false
    var photo: Image?
    var use: ArtUse = .walletDisplay

    @AppStorage("preferredName") private var preferredName = ""
    @Environment(\.colorSchemeContrast) private var contrast

    private var art: CardArt { CardArt.art(for: card.artKey) }

    var body: some View {
        let artwork = CardArtwork(card: card, photo: photo, use: use)
        GeometryReader { proxy in
            let radius = proxy.size.width * 0.055
            Group {
                if artwork.isLicensed, let image = artwork.image {
                    // No crop, corner mask, text or modification of a grant.
                    image.resizable().scaledToFit()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                } else {
                    ZStack {
                        if let image = artwork.image {
                            image.resizable().scaledToFill()
                                .frame(width: proxy.size.width, height: proxy.size.height)
                        } else {
                            CardMaterial(art: art, finish: card.appearance)
                            drawnContent
                                .frame(width: 344, height: 344 / 1.586)
                                .scaleEffect(proxy.size.width / 344, anchor: .topLeading)
                                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(colors: [.white.opacity(contrast == .increased ? 0.8 : 0.45), .white.opacity(0.08), .black.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: contrast == .increased ? 1.5 : 0.75
                            )
                    }
                }
            }
        }
        .aspectRatio(1.586, contentMode: .fit)
        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(artwork.source))
    }

    private var drawnContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.issuer)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text(card.name)
                        .font(.system(size: 23, weight: .semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: Metric.tight)
                if card.isPinned {
                    Image(systemName: "star.fill")
                        .font(.system(size: 12))
                }
            }
            Spacer(minLength: Metric.tight)
            HStack(spacing: Metric.snug) {
                EMVChip().frame(width: 39, height: 30)
                ContactlessMark()
                    .stroke(.white, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .frame(width: 17, height: 24)
                Spacer()
            }
            Spacer(minLength: Metric.tight)
            if let highlight {
                Text(highlight)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                    .padding(.bottom, Metric.tight)
            }
            HStack {
                Text(preferredName.trimmingCharacters(in: .whitespacesAndNewlines))
                    .lineLimit(1)
                Spacer(minLength: Metric.tight)
                Text(isRecommended ? "Use this card" : "CardAhead")
            }
            .font(.system(size: 11, weight: .medium))
        }
        .padding(Metric.wide)
        .foregroundStyle(.white)
    }

    private func accessibilityText(_ source: CardArtSource) -> String {
        var parts = [source.accessibilityDescription(for: card)]
        if let highlight { parts.append(highlight) }
        if isRecommended { parts.append("Recommended here") }
        if card.isPinned { parts.append("Preferred for ties") }
        return parts.joined(separator: ", ")
    }
}

/// Generic contact geometry, never an issuer logo.
struct EMVChip: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(LinearGradient(
                colors: [Color(red: 0.92, green: 0.86, blue: 0.65), Color(red: 0.64, green: 0.53, blue: 0.30), Color(red: 0.96, green: 0.91, blue: 0.76)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
            .overlay {
                GeometryReader { proxy in
                    let w = proxy.size.width, h = proxy.size.height
                    Path { path in
                        path.addRoundedRect(in: CGRect(x: w * 0.3, y: h * 0.14, width: w * 0.4, height: h * 0.72), cornerSize: CGSize(width: 2, height: 2))
                        for fraction in [0.33, 0.67] {
                            path.move(to: CGPoint(x: 0, y: h * fraction))
                            path.addLine(to: CGPoint(x: w * 0.3, y: h * fraction))
                            path.move(to: CGPoint(x: w * 0.7, y: h * fraction))
                            path.addLine(to: CGPoint(x: w, y: h * fraction))
                        }
                    }
                    .stroke(.black.opacity(0.4), lineWidth: 0.7)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(.black.opacity(0.3), lineWidth: 0.7)
            }
            .accessibilityHidden(true)
    }
}

private struct ContactlessMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for step in 1...3 {
            path.addArc(center: CGPoint(x: rect.minX, y: rect.midY), radius: rect.width * 0.3 * Double(step), startAngle: .degrees(-48), endAngle: .degrees(48), clockwise: false)
        }
        return path
    }
}

#Preview {
    VStack(spacing: 24) {
        CardFaceView(card: CardCatalog.amexGold)
        CardFaceView(card: CardCatalog.chaseFreedomFlex)
    }
    .padding()
}