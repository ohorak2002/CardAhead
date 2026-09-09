import SwiftUI

/// Card faces.
///
/// The app never sees a card number, so the face *is* the card's identity —
/// the user picks the colour closest to the plastic in their wallet and
/// recognises it in the stack the same way they recognise it in real life.
/// That makes this palette a functional part of the product, not decoration.
///
/// A deliberate limitation: these are colour treatments, not reproductions of
/// the real card art. Issuer logos and card designs are trademarked, and
/// shipping pixel copies of them needs a licence or issuer approval. Swap in
/// licensed assets here when you have them, and nothing else has to change.
struct CardArt: Hashable, Identifiable {
    var id: String { key }
    var key: String
    /// What the user is shown when picking. Plain colour words, not brand names.
    var label: String
    var colors: [Color]
    var foreground: Color
    var accent: Color

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - The palette

    /// Ordered for the picker grid. `palettes` and `art(for:)` read from this,
    /// so a new colour only has to be added once.
    static let ordered: [CardArt] = [
        CardArt(key: "midnight", label: "Midnight",
                colors: [Color(red: 0.09, green: 0.13, blue: 0.24), Color(red: 0.04, green: 0.06, blue: 0.13)],
                foreground: .white, accent: Color(red: 0.48, green: 0.65, blue: 0.96)),
        CardArt(key: "sapphire", label: "Blue",
                colors: [Color(red: 0.10, green: 0.29, blue: 0.55), Color(red: 0.05, green: 0.16, blue: 0.35)],
                foreground: .white, accent: Color(red: 0.65, green: 0.81, blue: 1.0)),
        CardArt(key: "azure", label: "Sky",
                colors: [Color(red: 0.16, green: 0.45, blue: 0.75), Color(red: 0.08, green: 0.28, blue: 0.52)],
                foreground: .white, accent: Color(red: 0.75, green: 0.88, blue: 1.0)),
        CardArt(key: "forest", label: "Green",
                colors: [Color(red: 0.13, green: 0.35, blue: 0.24), Color(red: 0.06, green: 0.20, blue: 0.14)],
                foreground: .white, accent: Color(red: 0.70, green: 0.92, blue: 0.79)),
        CardArt(key: "gold", label: "Gold",
                colors: [Color(red: 0.72, green: 0.60, blue: 0.34), Color(red: 0.47, green: 0.38, blue: 0.20)],
                foreground: .white, accent: Color(red: 1.0, green: 0.93, blue: 0.78)),
        CardArt(key: "graphite", label: "Graphite",
                colors: [Color(red: 0.25, green: 0.26, blue: 0.28), Color(red: 0.12, green: 0.13, blue: 0.15)],
                foreground: .white, accent: Color(red: 0.98, green: 0.68, blue: 0.25)),
        CardArt(key: "slate", label: "Steel",
                colors: [Color(red: 0.29, green: 0.33, blue: 0.38), Color(red: 0.17, green: 0.20, blue: 0.24)],
                foreground: .white, accent: Color(red: 0.77, green: 0.82, blue: 0.87)),
        CardArt(key: "ember", label: "Orange",
                colors: [Color(red: 0.72, green: 0.24, blue: 0.16), Color(red: 0.44, green: 0.12, blue: 0.09)],
                foreground: .white, accent: Color(red: 1.0, green: 0.82, blue: 0.72)),
        CardArt(key: "crimson", label: "Red",
                colors: [Color(red: 0.60, green: 0.09, blue: 0.16), Color(red: 0.35, green: 0.05, blue: 0.10)],
                foreground: .white, accent: Color(red: 1.0, green: 0.84, blue: 0.55)),
        CardArt(key: "plum", label: "Purple",
                colors: [Color(red: 0.30, green: 0.16, blue: 0.39), Color(red: 0.16, green: 0.07, blue: 0.22)],
                foreground: .white, accent: Color(red: 0.87, green: 0.75, blue: 0.96))
    ]

    static let fallback = ordered.first { $0.key == "slate" } ?? ordered[0]

    static let palettes: [String: CardArt] = Dictionary(
        uniqueKeysWithValues: ordered.map { ($0.key, $0) }
    )

    static func art(for key: String) -> CardArt {
        palettes[key] ?? fallback
    }
}
