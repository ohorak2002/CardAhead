import SwiftUI

/// Card faces.
///
/// A deliberate limitation: these are colour treatments keyed to each issuer's
/// familiar palette, with a text wordmark. They are not reproductions of the
/// real card art. Issuer logos and card designs are trademarked, and shipping
/// pixel copies of them needs a licence or issuer approval. The recognition
/// goal the product spec asks for is served by colour and layout; swap in
/// licensed assets here when you have them, and nothing else has to change.
struct CardArt: Hashable {
    var key: String
    var colors: [Color]
    var foreground: Color
    var accent: Color

    static let fallback = CardArt(
        key: "slate",
        colors: [Color(red: 0.29, green: 0.33, blue: 0.38), Color(red: 0.17, green: 0.20, blue: 0.24)],
        foreground: .white,
        accent: Color(red: 0.75, green: 0.80, blue: 0.86)
    )

    static let palettes: [String: CardArt] = [
        "midnight": CardArt(
            key: "midnight",
            colors: [Color(red: 0.09, green: 0.13, blue: 0.24), Color(red: 0.04, green: 0.06, blue: 0.13)],
            foreground: .white,
            accent: Color(red: 0.44, green: 0.62, blue: 0.94)
        ),
        "sapphire": CardArt(
            key: "sapphire",
            colors: [Color(red: 0.10, green: 0.29, blue: 0.55), Color(red: 0.05, green: 0.16, blue: 0.35)],
            foreground: .white,
            accent: Color(red: 0.62, green: 0.79, blue: 1.0)
        ),
        "graphite": CardArt(
            key: "graphite",
            colors: [Color(red: 0.25, green: 0.26, blue: 0.28), Color(red: 0.12, green: 0.13, blue: 0.15)],
            foreground: .white,
            accent: Color(red: 0.98, green: 0.68, blue: 0.25)
        ),
        "azure": CardArt(
            key: "azure",
            colors: [Color(red: 0.16, green: 0.45, blue: 0.75), Color(red: 0.08, green: 0.28, blue: 0.52)],
            foreground: .white,
            accent: Color(red: 0.72, green: 0.87, blue: 1.0)
        ),
        "gold": CardArt(
            key: "gold",
            colors: [Color(red: 0.72, green: 0.60, blue: 0.34), Color(red: 0.47, green: 0.38, blue: 0.20)],
            foreground: .white,
            accent: Color(red: 1.0, green: 0.93, blue: 0.78)
        ),
        "slate": fallback,
        "ember": CardArt(
            key: "ember",
            colors: [Color(red: 0.72, green: 0.24, blue: 0.16), Color(red: 0.44, green: 0.12, blue: 0.09)],
            foreground: .white,
            accent: Color(red: 1.0, green: 0.82, blue: 0.72)
        ),
        "crimson": CardArt(
            key: "crimson",
            colors: [Color(red: 0.60, green: 0.09, blue: 0.16), Color(red: 0.35, green: 0.05, blue: 0.10)],
            foreground: .white,
            accent: Color(red: 1.0, green: 0.84, blue: 0.55)
        ),
        "forest": CardArt(
            key: "forest",
            colors: [Color(red: 0.13, green: 0.35, blue: 0.24), Color(red: 0.06, green: 0.20, blue: 0.14)],
            foreground: .white,
            accent: Color(red: 0.70, green: 0.92, blue: 0.79)
        )
    ]

    static func art(for key: String) -> CardArt {
        palettes[key] ?? fallback
    }

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
