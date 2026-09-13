import SwiftUI
import UIKit
import CardKit

/// The shapes and spacings the redesign is built out of, in one place.
///
/// The mockup is consistent about a small number of things, and consistency is
/// most of what makes it read as designed rather than assembled: an 8-point
/// spacing grid, generously rounded corners, soft shadows that are tinted
/// rather than grey, and a single navy-to-blue gradient that appears on
/// exactly two surfaces. Scattering those values across a dozen views is how
/// they drift.
enum Metric {
    /// Everything is a multiple of 4, most things a multiple of 8.
    static let tight: CGFloat = 8
    static let snug: CGFloat = 12
    static let regular: CGFloat = 16
    static let roomy: CGFloat = 24
    static let loose: CGFloat = 32

    /// The screen's own left and right margin. One number, used everywhere,
    /// so nothing sits a few points off from the thing above it.
    static let margin: CGFloat = 20

    static let cardRadius: CGFloat = 20
    static let tileRadius: CGFloat = 16
    static let pillRadius: CGFloat = 10
}

extension Color {
    /// Primary Navy. The top of the brand gradient and nothing else — a navy
    /// this dark used as a fill swallows whatever sits on it.
    static let cardWiseNavy = Color(red: 0.043, green: 0.122, blue: 0.267)
    /// Secondary Blue, which is also the `AccentColor` asset. Declared here as
    /// a literal too, because a gradient needs a colour rather than a
    /// semantic tint that a parent view might have overridden.
    static let cardWiseBlue = Color(red: 0.118, green: 0.337, blue: 0.839)
    /// Accent Blue. The bottom of the lighter gradient.
    static let cardWiseAccent = Color(red: 0.231, green: 0.510, blue: 0.965)
}

extension ShapeStyle where Self == LinearGradient {
    /// Navy to Secondary Blue. The header on Home and the hero on Impact, and
    /// deliberately nowhere else — a gradient that turns up on every surface
    /// stops meaning anything.
    static var cardWiseHeader: LinearGradient {
        LinearGradient(
            colors: [.cardWiseNavy, .cardWiseBlue],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Secondary Blue to Accent Blue. Lighter, for a card sitting *on* a
    /// normal background rather than being the background.
    static var cardWiseAccentGradient: LinearGradient {
        LinearGradient(
            colors: [.cardWiseBlue, .cardWiseAccent],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Category colour

/// A colour and a symbol per benefit shelf.
///
/// These are wayfinding, not decoration: the same green circle means groceries
/// on the Benefits grid, in the expiring list and beside a recommendation, so
/// the shelf becomes recognisable before the label is read. They come off the
/// brand palette sheet rather than from SwiftUI's system colours, which shift
/// between iOS releases.
extension BenefitGroup {

    var tint: Color {
        switch self {
        case .dining: return Color(red: 0.118, green: 0.337, blue: 0.839)      // Secondary Blue
        case .travel: return Color(red: 0.231, green: 0.510, blue: 0.965)      // Accent Blue
        case .groceries: return Color(red: 0.063, green: 0.725, blue: 0.506)   // Success Green
        case .gas: return Color(red: 0.545, green: 0.361, blue: 0.965)         // Purple
        case .entertainment: return Color(red: 0.078, green: 0.722, blue: 0.651) // Teal
        case .drugstores: return Color(red: 0.937, green: 0.267, blue: 0.267)  // Error Red
        case .shopping: return Color(red: 0.976, green: 0.451, blue: 0.086)    // Orange
        case .everydaySpending: return Color(red: 0.392, green: 0.455, blue: 0.545) // Slate
        case .cardPerks: return Color(red: 0.043, green: 0.122, blue: 0.267)   // Navy
        case .creditsAndBonuses: return Color(red: 0.961, green: 0.620, blue: 0.043) // Warning
        }
    }

    var symbolName: String {
        switch self {
        case .dining: return "fork.knife"
        case .travel: return "airplane"
        case .groceries: return "basket.fill"
        case .gas: return "bolt.car.fill"
        case .entertainment: return "play.tv.fill"
        case .drugstores: return "cross.case.fill"
        case .shopping: return "bag.fill"
        case .everydaySpending: return "circle.grid.2x2.fill"
        case .cardPerks: return "shield.lefthalf.filled"
        case .creditsAndBonuses: return "gift.fill"
        }
    }
}

extension SpendingCategory {
    /// Borrowed from the shelf it belongs to, so a category and its group are
    /// never two different colours for the same thing.
    var tint: Color { BenefitGroup.containing(self).tint }
    var symbolName: String { BenefitGroup.containing(self).symbolName }
}

// MARK: - Pieces

/// A rounded square holding one symbol, in its category's colour at low
/// opacity. The mockup's most repeated element.
struct CategoryIcon: View {
    let symbolName: String
    let tint: Color
    var size: CGFloat = 40

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(tint.opacity(0.14))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbolName)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .accessibilityHidden(true)
    }
}

/// One number with a word under it. Three of these in a row is how the card
/// detail and impact screens open.
struct StatTile: View {
    let value: String
    let label: String
    var tint: Color?

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(tint ?? Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Metric.snug)
        // A tile sits *on* a panel, so it takes the role one step further in
        // than the panel's own — same reasoning as `PanelBackground`, one
        // level down.
        .background(
            Color(.tertiarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: Metric.tileRadius, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

/// The surface most content sits on: a rounded panel with a soft, *tinted*
/// shadow rather than a grey one. Grey shadows on a coloured ground are the
/// single most common tell of an interface nobody looked at twice.
///
/// **The fill is `secondarySystemGroupedBackground`, not `.background`, and
/// the difference only shows at night.** `.background` is `systemBackground`,
/// which is pure black in dark mode — and every screen in this app sits on
/// `systemGroupedBackground`, which is *also* pure black. So a panel drawn
/// with it was black on black, and the only thing separating a row from the
/// page was a navy shadow that is itself invisible against black. The
/// screenshots of the map's list showed a column of floating text with no
/// cards under it at all.
///
/// The grouped-secondary role is the one that means exactly this: a card
/// sitting on a grouped page. White on light, near-black-but-not-black on
/// dark, and it stays correct if Apple ever moves either.
struct PanelBackground: ViewModifier {
    var radius: CGFloat = Metric.cardRadius

    func body(content: Content) -> some View {
        content
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .shadow(color: Color.cardWiseNavy.opacity(0.07), radius: 12, x: 0, y: 4)
    }
}

extension View {
    func cardWisePanel(radius: CGFloat = Metric.cardRadius) -> some View {
        modifier(PanelBackground(radius: radius))
    }
}

/// A small capsule of text. Used for "Best for Dining" and nothing that needs
/// to be read at a glance from across the room — pills are a garnish, and the
/// mockup uses exactly one per row for a reason.
struct TagPill: View {
    let text: String
    var tint: Color = .cardWiseBlue

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, Metric.tight)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Metric.pillRadius, style: .continuous))
    }
}

/// A section title with an optional action on the right.
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
            Spacer(minLength: Metric.tight)
            trailing
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title: title) { EmptyView() }
    }
}

/// A bank, as a coloured square with its initials in it.
///
/// **Deliberately not the bank's logo, and deliberately not the bank's
/// colours.** An issuer's mark and its trade dress are its own; a blue square
/// reading "AE" next to the words "American Express" is the app's styling of a
/// name it is entitled to say, which is a different thing from a reproduction
/// of a brand. The colour comes off CardWise's own palette, picked
/// deterministically from the name so a bank looks the same on every launch
/// and in every list — recognisable at a glance, which is the whole job — and
/// never matches what the issuer actually uses.
struct IssuerMonogram: View {
    let name: String
    var size: CGFloat = 38

    /// Two letters: the initials of the first two words, or the first two
    /// letters of a one-word name. "Chase" is CH, "American Express" is AE.
    private var initials: String {
        let words = name.split(separator: " ").filter { !$0.isEmpty }
        if words.count >= 2 {
            return words.prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    /// Stable across launches: Swift's `hashValue` is seeded per-process and
    /// would give the same bank a different colour every time the app opened.
    private var tint: Color {
        let palette: [Color] = [
            .cardWiseNavy,
            .cardWiseBlue,
            .cardWiseAccent,
            Color(red: 0.063, green: 0.725, blue: 0.506),
            Color(red: 0.545, green: 0.361, blue: 0.965),
            Color(red: 0.078, green: 0.722, blue: 0.651),
            Color(red: 0.976, green: 0.451, blue: 0.086)
        ]
        let sum = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[sum % palette.count]
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(tint.opacity(0.14))
            .frame(width: size, height: size)
            .overlay {
                Text(initials)
                    .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
            }
            .accessibilityHidden(true)
    }
}

/// The navy top the whole app wears.
///
/// Home had this and the other tabs had a plain system title on a black
/// ground, which made Home look like a different app's front door rather than
/// this app's. One header, used everywhere, is most of what makes a set of
/// screens read as one product.
///
/// It replaces the navigation bar rather than sitting under it — the tab roots
/// have nothing to navigate back to, so the bar was only ever holding a title
/// and, on the wallet, a plus. Both live here now.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: Metric.tight)
                trailing
            }
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Metric.margin)
        .padding(.top, Metric.roomy)
        .padding(.bottom, Metric.roomy)
        // **The gradient reaches under the status bar; the text does not.**
        // `ignoresSafeArea` applied to the header itself moves the whole
        // thing up, and the title lands on top of the clock. Applied to the
        // background shape alone, only the paint extends.
        .background {
            UnevenRoundedRectangle(
                bottomLeadingRadius: 28,
                bottomTrailingRadius: 28,
                style: .continuous
            )
            .fill(.cardWiseHeader)
            .ignoresSafeArea(edges: .top)
        }
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// The circular button that sits in a `ScreenHeader` — white on navy, which
/// the system toolbar button is not.
struct HeaderButton: View {
    let symbolName: String
    let label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.18), in: Circle())
        }
        .accessibilityLabel(label)
    }
}
