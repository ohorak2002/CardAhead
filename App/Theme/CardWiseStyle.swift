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
    /// The whole scale: 8, 12, 16, 20, 24, 32, 40. Seven steps, no others.
    /// A padding value that is not one of these is a value somebody picked by
    /// eye, and by the tenth screen nothing lines up with anything.
    static let tight: CGFloat = 8
    static let snug: CGFloat = 12
    static let regular: CGFloat = 16
    /// Also the screen's own left and right margin — one number, used
    /// everywhere, so nothing sits a few points off from the thing above it.
    static let wide: CGFloat = 20
    static let roomy: CGFloat = 24
    static let loose: CGFloat = 32
    /// The gap that separates *subjects* rather than elements. Between the
    /// last row of one section and the heading of the next, where the reader
    /// should feel a change of topic.
    static let section: CGFloat = 40

    /// The screen margin. Same number as `wide`, named for its job, because
    /// "the page margin" and "a wide gap" change for different reasons.
    static let margin: CGFloat = 20
    static let minimumTarget: CGFloat = 44

    // MARK: - Corners
    //
    // Three radii, in a deliberate order. A card is the most rounded thing on
    // screen because it is standing in for a physical object; a row is barely
    // rounded because it is a piece of paper. Everything at the same radius
    // is what makes an interface read as a set of coloured boxes.

    /// A card face, and panels that hold one.
    static let cardRadius: CGFloat = 20
    /// A tile or a grouped row — the common case.
    static let tileRadius: CGFloat = 16
    /// A small control: a badge, a chip's corner when it is not a capsule.
    static let pillRadius: CGFloat = 10

    // MARK: - Elevation
    //
    // **Two levels, and most things are at neither.** A shadow means "this
    // is above the page"; if everything has one, nothing is. Both are navy
    // rather than grey — a grey shadow on a coloured ground is the single
    // most common tell of an interface nobody looked at twice.

    /// A panel resting on the page. Barely there on purpose.
    static let restingShadow: (radius: CGFloat, y: CGFloat, opacity: Double) = (12, 4, 0.07)
    /// Something genuinely lifted: a card under a finger, a sheet over
    /// content. Used in a handful of places, never as decoration.
    static let liftedShadow: (radius: CGFloat, y: CGFloat, opacity: Double) = (22, 10, 0.16)
}

extension Color {
    /// Primary Navy. The top of the brand gradient and nothing else — a navy
    /// this dark used as a fill swallows whatever sits on it.
    static let cardWiseNavy = Color(red: 0.043, green: 0.122, blue: 0.267)
    /// Secondary Blue, which is also the `AccentColor` asset. Declared here as
    /// a literal too, because a gradient needs a colour rather than a
    /// semantic tint that a parent view might have overridden.
    static let cardWiseBlue = Color(red: 0.118, green: 0.337, blue: 0.839)
    /// Text and controls on semantic surfaces; fixed brand blue stays in fills.
    static let cardWiseActionInk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.56, green: 0.73, blue: 1.0, alpha: 1)
            : UIColor(red: 0.08, green: 0.27, blue: 0.70, alpha: 1)
    })
    /// Accent Blue. The bottom of the lighter gradient.
    static let cardWiseAccent = Color(red: 0.231, green: 0.510, blue: 0.965)
    /// Light Blue. The only palette colour that can tint text **on** the
    /// header gradient.
    ///
    /// The mockup puts the name in the greeting in Accent Blue, and that
    /// cannot be copied: Accent Blue on the gradient's lighter end is
    /// **1.70:1**, worse than the invisible Card perks icon that `BrandTint`
    /// exists because of. Light Blue is 5.51:1 at the same spot and reads as
    /// the same idea — a name picked out from the words around it.
    static let cardWiseLightBlue = Color(red: 0.902, green: 0.949, blue: 1.0)

    // MARK: - The neutrals, at last, and only where the system has no opinion
    //
    // **These were deliberately absent and the reason still stands**, so read
    // it before reaching for one. `.primary`, `.secondary` and the system
    // background roles already mean "body text", "supporting text" and "the
    // page", and they adapt to Dark Mode on their own. Hardcoding the palette
    // sheet's Charcoal as body text would look right once, in daylight, on the
    // day it was written, and read as low-contrast grey the first time
    // somebody opened the app at night.
    //
    // So the rule is unchanged: **text and backgrounds keep using the system
    // roles.** What these are for is the handful of places with no system
    // equivalent — a border that must be visible against a white card, the
    // ground behind a card face, a divider inside a panel. Each is an asset
    // catalog entry with a light and a dark value, like the status colours,
    // never a single hex baked into Swift.

    /// Light Gray by day, a lifted charcoal by night. Hairlines, dividers
    /// inside a panel, and the border on an unselected control — the places
    /// `.separator` is too faint because the surface is already white.
    static let cardWiseHairline = Color("CardWiseHairline", bundle: .main)

    /// Off White by day, true charcoal by night. The ground a card face sits
    /// on when it needs to be distinguishable from the page *and* from a
    /// panel — the card preview on Add Card, mainly.
    static let cardWiseCanvas = Color("CardWiseCanvas", bundle: .main)
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

// MARK: - Haptics

/// Something that happened, counted, so a haptic can fire on it.
///
/// `sensoryFeedback(_:trigger:)` watches a value for a *change*, which makes
/// the obvious thing wrong: triggering on the card that was removed means
/// removing the same card twice in a row fires once, and triggering on
/// `cards.count` means an add and a remove feel identical. A counter says
/// "this happened again" and nothing else, which is exactly what a haptic
/// needs to know.
///
/// **Not gated on Reduce Motion.** A haptic is not motion, and iOS already has
/// its own switch for this — Settings › Sounds & Haptics › System Haptics —
/// which `sensoryFeedback` honours on its own. Second-guessing it in the app
/// would take the choice away from somebody who has already made it.
///
/// Usage:
/// ```swift
/// @State private var removed = Pulse()
/// // ...
/// Button("Remove") { removed.fire(); store.remove(card) }
///     .sensoryFeedback(.impact(weight: .medium), trigger: removed)
/// ```
struct Pulse: Equatable {
    private var count = 0

    /// Wrapping addition, because a counter that traps on overflow after two
    /// billion taps is a crash nobody would ever diagnose.
    mutating func fire() {
        count &+= 1
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
extension TintRGB {
    /// The one place a CardKit palette number becomes something SwiftUI can
    /// draw. Everything else asks `BrandTint` for a value and comes here.
    var color: Color {
        Color(red: red / 255, green: green / 255, blue: blue / 255)
    }

    var uiColor: UIColor {
        UIColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
    }
}

extension BrandTint {
    /// A colour that resolves itself against whatever mode the phone is in.
    ///
    /// `UIColor`'s trait-provider rather than two `Color`s picked in a view,
    /// because the mode can change while a view is on screen — Control Centre,
    /// sunset, Settings — and a value read once at body-evaluation time does
    /// not notice. A dynamic `UIColor` is re-resolved by the render server.
    var adaptive: Color {
        // Hoisted out of the closure, and deliberately not named `light` and
        // `dark`: `let light = light.uiColor` inside a member is a variable
        // used within its own initial value, which is a compile error and a
        // confusing one to read.
        let byDay = light.uiColor
        let byNight = dark.uiColor
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? byNight : byDay
        })
    }
}

extension BenefitGroup {

    /// The colour of this shelf's icon and its rate, against a background that
    /// follows the interface style.
    ///
    /// **The values moved to CardKit and this is now a lookup.** They used to
    /// be ten hex literals right here, one per shelf, each used unchanged in
    /// both modes — which is how the Card perks shield came to be drawn in
    /// Primary Navy on a near-black tile at a contrast ratio of 1.05:1, i.e.
    /// invisible. Four shelves failed in one mode or the other. In CardKit
    /// they are plain numbers, and `BrandTintTests` fails the build if any of
    /// them stops clearing 3:1 against what it is actually drawn on.
    var tint: Color { tintPalette.adaptive }

    /// The colour of a **solid** fill with a white glyph on it — a map pin.
    ///
    /// Deliberately not `tint`. See `BrandTint.solid`: a wash needs the value
    /// that contrasts with the page, a pin needs the value that a white symbol
    /// survives on, and in dark mode those are opposite ends of the palette.
    /// Feeding `tint` to a pin is what put white symbols on Success Green at
    /// 2.54:1.
    var pinTint: Color { tintPalette.solid.color }

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
    var pinTint: Color { BenefitGroup.containing(self).pinTint }
    var symbolName: String { BenefitGroup.containing(self).symbolName }

    /// The glyph on a notification badge, which is **not** the shelf's.
    ///
    /// **Found by photographing all seventeen side by side, and obvious the
    /// moment they were.** The shelf symbol is a symbol for a *group* — the
    /// Benefits screen has one row per shelf, so an aeroplane meaning "travel"
    /// is exactly right there. A notification badge is about one specific
    /// place, and borrowing the group's glyph made seven of the seventeen the
    /// same blue aeroplane: a hotel, a subway station, a taxi and an airport
    /// all wore an identical chip. Groceries and a warehouse club shared a
    /// basket; three kinds of shopping shared a bag.
    ///
    /// The whole job of the chip is to say what kind of place this is before a
    /// word is read, and seven identical ones cannot do it. The colours still
    /// come from the shelf — a family resemblance across travel is useful —
    /// but the glyph is per category.
    ///
    /// `gas` is the one that was also plain wrong rather than merely
    /// duplicated: the shelf uses `bolt.car.fill`, which is a charging point.
    var badgeSymbolName: String {
        switch self {
        case .base: return "creditcard.fill"
        case .dining: return "fork.knife"
        case .groceries: return "basket.fill"
        case .warehouseClub: return "shippingbox.fill"
        case .gas: return "fuelpump.fill"
        case .drugstores: return "cross.case.fill"
        case .travel: return "suitcase.fill"
        case .travelPortal: return "globe.americas.fill"
        case .flights: return "airplane"
        case .hotels: return "bed.double.fill"
        case .transit: return "tram.fill"
        case .rideshare: return "car.fill"
        case .streaming: return "play.tv.fill"
        case .entertainment: return "ticket.fill"
        case .onlineShopping: return "bag.fill"
        case .homeImprovement: return "hammer.fill"
        case .departmentStore: return "building.2.fill"
        }
    }
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
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: Metric.tight) {
                Text(title)
                    .font(.system(typeSize.isAccessibilitySize ? .title2 : .largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Metric.tight)
                trailing
            }
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white)
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
                .frame(width: Metric.minimumTarget, height: Metric.minimumTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }
}
