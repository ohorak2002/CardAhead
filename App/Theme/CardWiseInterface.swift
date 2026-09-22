import SwiftUI
import UIKit

/// App chrome only. These roles never feed card artwork or notification badges.
enum InterfacePalette {
    static let page = adaptive(0xF7FAFF, 0x0C1424)
    static let surface = adaptive(0xFFFFFF, 0x152238)
    static let wash = adaptive(0xEAF2FF, 0x1B304D)
    static let ink = adaptive(0x0B2253, 0xE8F0FF)
    static let secondary = adaptive(0x526A8E, 0xA8BBD7)
    static let line = adaptive(0xD9E6FA, 0x30435D)
    static let blue = adaptive(0x005BEA, 0x8AB9FF)
    static let cyan = Color(red: 0.26, green: 0.80, blue: 1)

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((rgb >> 16) & 255) / 255,
                green: CGFloat((rgb >> 8) & 255) / 255,
                blue: CGFloat(rgb & 255) / 255,
                alpha: 1
            )
        })
    }
}

struct InterfacePanel: ViewModifier {
    var tinted = false

    func body(content: Content) -> some View {
        content
            .background(tinted ? InterfacePalette.wash : InterfacePalette.surface,
                        in: RoundedRectangle(cornerRadius: Metric.tileRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Metric.tileRadius, style: .continuous)
                    .strokeBorder(InterfacePalette.line.opacity(0.8), lineWidth: 0.75)
            }
    }
}

extension View {
    func interfacePanel(tinted: Bool = false) -> some View {
        modifier(InterfacePanel(tinted: tinted))
    }
}

/// A directional glow gives the Home header depth without an image download.
struct HomeAtmosphere: View {
    var body: some View {
        LinearGradient(
            colors: [Color(red: 0.025, green: 0.12, blue: 0.30),
                     Color(red: 0.015, green: 0.055, blue: 0.17)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .overlay {
            RadialGradient(
                colors: [Color.cardWiseBlue.opacity(0.45), .clear],
                center: .topTrailing, startRadius: 0, endRadius: 350
            )
        }
    }
}

/// Bundled issuer identifiers, shown only beside a bank name in the picker.
/// No network request, tracking endpoint, or generated approximation of a logo.
struct IssuerLogo: View {
    let name: String
    var size: CGFloat = 40

    private var asset: String? {
        switch name {
        case "American Express", "Amex": return "IssuerAmex"
        case "Chase": return "IssuerChase"
        case "Capital One": return "IssuerCapitalOne"
        case "Citi": return "IssuerCiti"
        case "Discover": return "IssuerDiscover"
        case "Wells Fargo": return "IssuerWellsFargo"
        default: return nil
        }
    }

    var body: some View {
        Group {
            if let asset {
                Image(asset)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
                    .frame(width: size, height: size)
                    // Logos retain their original colors in both appearances.
                    .background(.white, in: RoundedRectangle(cornerRadius: Metric.pillRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: Metric.pillRadius)
                            .strokeBorder(InterfacePalette.line, lineWidth: 0.75)
                    }
            } else {
                IssuerMonogram(name: name, size: size)
            }
        }
        .accessibilityHidden(true)
    }
}

struct AddCardProgress: View {
    let step: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...3, id: \.self) { index in
                Capsule()
                    .fill(index <= step ? InterfacePalette.blue : InterfacePalette.line)
                    .frame(width: index == step ? 24 : 8, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step) of 3")
    }
}
