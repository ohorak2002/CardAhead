import SwiftUI
import CardKit

/// The card itself. The top strip is the only part visible while stacked, so
/// everything needed to recognise the card lives there: issuer, name, and the
/// one thing it is best at.
struct CardFaceView: View {
    let card: Card
    var highlight: String?

    @ScaledMetric(relativeTo: .title3) private var cornerRadius: CGFloat = 18

    private var art: CardArt { CardArt.art(for: card.artKey) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(card.issuer)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(art.foreground.opacity(0.85))
                Spacer(minLength: 8)
                if card.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(art.accent)
                        .accessibilityLabel("Pinned")
                }
            }

            Text(card.name)
                .font(.title3.weight(.bold))
                .foregroundStyle(art.foreground)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            if let highlight {
                Text(highlight)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(art.accent)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack(alignment: .bottom) {
                Text(card.currency.name)
                    .font(.caption2)
                    .foregroundStyle(art.foreground.opacity(0.7))
                Spacer(minLength: 8)
                if card.annualFeeDollars > 0 {
                    Text(annualFeeText)
                        .font(.caption2)
                        .foregroundStyle(art.foreground.opacity(0.7))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(art.gradient)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var annualFeeText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        let amount = formatter.string(from: NSDecimalNumber(decimal: card.annualFeeDollars)) ?? ""
        return "\(amount) a year"
    }

    private var accessibilityText: String {
        var parts = [card.displayName]
        if let highlight { parts.append(highlight) }
        if card.isPinned { parts.append("Pinned") }
        return parts.joined(separator: ", ")
    }
}

#Preview {
    VStack(spacing: 16) {
        CardFaceView(card: CardCatalog.amexGold, highlight: "4x dining")
        CardFaceView(card: CardCatalog.chaseFreedomFlex, highlight: "5% rotating this quarter")
    }
    .frame(height: 420)
    .padding()
}
