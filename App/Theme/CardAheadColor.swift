import SwiftUI

/// The CardAhead brand palette — chosen alongside the app icon, given as a
/// swatch sheet with named hex values, and wired in here rather than
/// scattered as `.orange` and `.green` through a dozen views.
///
/// **Deliberately separate from `CardArt`.** That palette is the colours a
/// person picks so their own card is recognisable in the stack, and it has to
/// stay wide open — nobody's Amex is "brand blue", and a card face that
/// matched the app's own colour scheme regardless of what the user picked
/// would stop being a useful way to tell cards apart. This file is the
/// opposite: it is the app's *own* identity, applied to its chrome — buttons,
/// status colours, the icon — and it must never leak onto a card face.
///
/// **Neutrals are deliberately absent.** The palette sheet names a Charcoal,
/// a Slate Gray, a Light Gray and an Off White, but SwiftUI's `.primary`,
/// `.secondary` and the system background materials already mean those roles
/// and adapt to Dark Mode on their own. Hardcoding the sheet's neutral hex
/// values would look right once, in light mode, on the day this was written,
/// and read as low-contrast text the first time somebody opens the app at
/// night. Every place that already used `.primary`/`.secondary` keeps doing
/// so; only identity and status colours move to named brand colours.
///
/// Each colour is a named entry in `Assets.xcassets` with a light and a dark
/// value, not a single hex baked into Swift — a colour picked to sit on white
/// paper is rarely the right colour to sit on near-black, and the asset
/// catalog is where that adjustment belongs.
extension Color {

    /// Success Green. A geofence confirmed, a rotating quarter switched on,
    /// a cap with room left. Replaces the system `.green` these states used
    /// before this palette existed.
    static let cardAheadSuccess = Color("CardAheadSuccess", bundle: .main)

    /// Warning Yellow. Reminders off, location blocked, a cap used up, a
    /// quarter not yet activated — anything that wants a glance before it
    /// becomes a problem. Replaces the system `.orange` these states used
    /// before this palette existed; every one of those call sites is now this
    /// colour, so "needs attention" reads the same shade everywhere in the
    /// app rather than whatever iOS calls orange this year.
    static let cardAheadWarning = Color("CardAheadWarning", bundle: .main)

    /// Error Red. Reserved, not yet load-bearing: SwiftUI's own
    /// `role: .destructive` already renders "Remove" and "Clear this list" in
    /// the system red, and duplicating that by hand would only risk the two
    /// reds drifting apart. Named here so the day a non-button error surface
    /// exists — a failed save, a corrupted wallet file — it reaches for this
    /// colour instead of a fresh, unrelated `.red`.
    static let cardAheadError = Color("CardAheadError", bundle: .main)
}
