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
    /// The surface texture under the colour. Derived from the palette rather
    /// than chosen separately, so this costs the user no extra decision and
    /// costs the wallet file no extra field — see `CardPattern`.
    ///
    /// Declared here, above `colors`, because the memberwise initialiser takes
    /// its arguments in declaration order and every entry below passes it here.
    var pattern: CardPattern = .none
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
        CardArt(key: "midnight", label: "Midnight", pattern: .concentricArcs,
                colors: [Color(red: 0.09, green: 0.13, blue: 0.24), Color(red: 0.04, green: 0.06, blue: 0.13)],
                foreground: .white, accent: Color(red: 0.48, green: 0.65, blue: 0.96)),
        CardArt(key: "sapphire", label: "Blue", pattern: .diagonalHairlines,
                colors: [Color(red: 0.10, green: 0.29, blue: 0.55), Color(red: 0.05, green: 0.16, blue: 0.35)],
                foreground: .white, accent: Color(red: 0.65, green: 0.81, blue: 1.0)),
        CardArt(key: "azure", label: "Sky", pattern: .softBloom,
                colors: [Color(red: 0.16, green: 0.45, blue: 0.75), Color(red: 0.08, green: 0.28, blue: 0.52)],
                foreground: .white, accent: Color(red: 0.75, green: 0.88, blue: 1.0)),
        CardArt(key: "forest", label: "Green", pattern: .fineGrid,
                colors: [Color(red: 0.13, green: 0.35, blue: 0.24), Color(red: 0.06, green: 0.20, blue: 0.14)],
                foreground: .white, accent: Color(red: 0.70, green: 0.92, blue: 0.79)),
        CardArt(key: "gold", label: "Gold", pattern: .verticalRibs,
                colors: [Color(red: 0.72, green: 0.60, blue: 0.34), Color(red: 0.47, green: 0.38, blue: 0.20)],
                foreground: .white, accent: Color(red: 1.0, green: 0.93, blue: 0.78)),
        CardArt(key: "graphite", label: "Graphite", pattern: .diagonalHairlines,
                colors: [Color(red: 0.25, green: 0.26, blue: 0.28), Color(red: 0.12, green: 0.13, blue: 0.15)],
                foreground: .white, accent: Color(red: 0.98, green: 0.68, blue: 0.25)),
        CardArt(key: "slate", label: "Steel", pattern: .fineGrid,
                colors: [Color(red: 0.29, green: 0.33, blue: 0.38), Color(red: 0.17, green: 0.20, blue: 0.24)],
                foreground: .white, accent: Color(red: 0.77, green: 0.82, blue: 0.87)),
        CardArt(key: "ember", label: "Orange", pattern: .softBloom,
                colors: [Color(red: 0.72, green: 0.24, blue: 0.16), Color(red: 0.44, green: 0.12, blue: 0.09)],
                foreground: .white, accent: Color(red: 1.0, green: 0.82, blue: 0.72)),
        CardArt(key: "crimson", label: "Red", pattern: .concentricArcs,
                colors: [Color(red: 0.60, green: 0.09, blue: 0.16), Color(red: 0.35, green: 0.05, blue: 0.10)],
                foreground: .white, accent: Color(red: 1.0, green: 0.84, blue: 0.55)),
        CardArt(key: "plum", label: "Purple", pattern: .verticalRibs,
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

// MARK: - Surface patterns

/// The texture under a drawn card's colour.
///
/// **These are CardWise's own, and deliberately abstract.** They are textures a
/// premium card could plausibly have — hairlines, a fine grid, turned arcs —
/// not versions of anything a particular bank prints. Recreating an issuer's
/// pattern is the same problem as copying their file, and a recoloured
/// near-miss is worse than either, so none of these is drawn from one.
///
/// They earn their place twice over. A plain gradient reads as a fallback; a
/// surface that catches light reads as an object. And because each colour in
/// the palette carries its own, two dark cards in the stack are told apart by
/// texture as well as hue — which is the whole job of this screen.
///
/// Every one of them is drawn at single-digit opacity. That is not timidity:
/// the moment a pattern is legible as a pattern, it stops looking like a card
/// and starts looking like wallpaper.
enum CardPattern: String, Hashable, CaseIterable {
    case none
    /// Fine lines at 45°. The most neutral of the set.
    case diagonalHairlines
    /// A quiet graph-paper grid.
    case fineGrid
    /// Turned arcs sweeping out of one corner.
    case concentricArcs
    /// A single soft light source, off-centre. No lines at all.
    case softBloom
    /// Narrow vertical bands, the way a brushed sheet catches light end-on.
    case verticalRibs
}

/// Draws a `CardPattern` across the full card face.
///
/// One `Canvas` rather than a stack of shapes, and the path counts are kept in
/// the tens: this is drawn once per card and the wallet scrolls with several on
/// screen at once.
struct CardPatternLayer: View {
    let pattern: CardPattern

    var body: some View {
        Canvas { context, size in
            switch pattern {
            case .none:
                break
            case .diagonalHairlines:
                drawDiagonals(in: &context, size: size)
            case .fineGrid:
                drawGrid(in: &context, size: size)
            case .concentricArcs:
                drawArcs(in: &context, size: size)
            case .softBloom:
                drawBloom(in: &context, size: size)
            case .verticalRibs:
                drawRibs(in: &context, size: size)
            }
        }
        // Canvas has an ideal size of its own; this makes it take the card's
        // instead, so a pattern cannot come out drawn in a corner.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private func drawDiagonals(in context: inout GraphicsContext, size: CGSize) {
        let spacing: CGFloat = 13
        var x = -size.height
        while x < size.width + size.height {
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x + size.height, y: size.height))
            context.stroke(path, with: .color(.white.opacity(0.055)), lineWidth: 1)
            x += spacing
        }
    }

    private func drawGrid(in context: inout GraphicsContext, size: CGSize) {
        let spacing: CGFloat = 15
        var path = Path()
        var x = spacing
        while x < size.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            x += spacing
        }
        var y = spacing
        while y < size.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            y += spacing
        }
        context.stroke(path, with: .color(.white.opacity(0.042)), lineWidth: 0.7)
    }

    private func drawArcs(in context: inout GraphicsContext, size: CGSize) {
        // Centred outside the card, bottom right, so only the sweep crosses the
        // face and no ring ever closes into a target.
        let centre = CGPoint(x: size.width * 1.02, y: size.height * 1.18)
        for step in 1...10 {
            var path = Path()
            path.addArc(
                center: centre,
                radius: size.height * (0.17 * CGFloat(step)),
                startAngle: .degrees(175),
                endAngle: .degrees(280),
                clockwise: false
            )
            context.stroke(path, with: .color(.white.opacity(0.05)), lineWidth: 1.1)
        }
    }

    private func drawBloom(in context: inout GraphicsContext, size: CGSize) {
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(
                Gradient(colors: [.white.opacity(0.13), .white.opacity(0)]),
                center: CGPoint(x: size.width * 0.76, y: size.height * 0.18),
                startRadius: 0,
                endRadius: size.width * 0.62
            )
        )
    }

    private func drawRibs(in context: inout GraphicsContext, size: CGSize) {
        let spacing: CGFloat = 7
        var x: CGFloat = 0
        var lit = true
        while x < size.width {
            let rect = CGRect(x: x, y: 0, width: spacing / 2, height: size.height)
            context.fill(
                Path(rect),
                with: .color(lit ? Color.white.opacity(0.045) : Color.black.opacity(0.035))
            )
            lit.toggle()
            x += spacing / 2
        }
    }
}
