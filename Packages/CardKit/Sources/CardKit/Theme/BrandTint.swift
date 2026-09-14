import Foundation

/// A colour as three numbers, and the arithmetic needed to prove it is
/// legible.
///
/// **Why a colour lives in CardKit, of all places.** CardKit is the layer with
/// no SwiftUI in it, which is exactly what makes a colour testable here: a
/// `Color` is an opaque handle that only means something once a view renders
/// it, but three doubles and a contrast formula are plain data that
/// `swift test` can check in milliseconds without booting a simulator. The app
/// layer turns these into `Color`s; the numbers themselves, and the question
/// of whether anybody can see them, stay here.
///
/// This exists because of a bug the CI screenshots caught that reading the
/// diff never would have: the Card perks icon was Primary Navy drawn on a
/// near-black tile, a contrast ratio of **1.05:1**, which is to say it was not
/// there at all. The line of code looked perfectly reasonable. Four of the ten
/// benefit shelves failed in one mode or the other, and every one of them
/// failed for the same reason — a single hex value used in both modes, on a
/// background that moves when the mode does.
public struct TintRGB: Sendable, Equatable, Hashable {

    /// 0...255, matching how the palette sheet states them.
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// `TintRGB(hex: 0x1E56D6)` — the form the brand sheet is written in, so a
    /// value can be copied across without being converted by hand first.
    public init(hex: UInt32) {
        self.init(
            Double((hex >> 16) & 0xFF),
            Double((hex >> 8) & 0xFF),
            Double(hex & 0xFF)
        )
    }

    /// 0...1, as WCAG defines it.
    public var relativeLuminance: Double {
        func channel(_ value: Double) -> Double {
            let v = value / 255
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// 1.0 for two identical colours, 21.0 for black on white.
    ///
    /// WCAG 1.4.11 asks for **3:1** for a graphic that carries meaning, which
    /// every icon in this app does — the colour is how a shelf is recognised
    /// before its label is read.
    public func contrastRatio(against other: TintRGB) -> Double {
        let a = relativeLuminance
        let b = other.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// This colour laid over `background` at `alpha`.
    ///
    /// **A straight blend in sRGB, deliberately not in linear light.** That is
    /// what CoreAnimation actually does, and it was checked rather than
    /// assumed: blending Secondary Blue at 14% over white predicts
    /// (223.5, 231.3, 249.3), and the pixel in the CI screenshot is
    /// (223, 230, 249). Blending in linear light would be more correct in the
    /// abstract and would not describe the thing on the screen.
    public func blended(alpha: Double, over background: TintRGB) -> TintRGB {
        TintRGB(
            alpha * red + (1 - alpha) * background.red,
            alpha * green + (1 - alpha) * background.green,
            alpha * blue + (1 - alpha) * background.blue
        )
    }

    public static let white = TintRGB(hex: 0xFFFFFF)
    public static let black = TintRGB(hex: 0x000000)
}

/// Light or dark, as a value a test can iterate.
public enum InterfaceStyle: String, Sendable, CaseIterable {
    case light
    case dark
}

/// One palette entry: what a colour is by day, and what it is at night.
///
/// **Two values rather than one is the whole point.** A hue picked to sit on
/// white paper is rarely the hue that sits on near-black, and the app's own
/// `CardWiseColor` already learned this — those are asset-catalog colour sets
/// with both values in them. The benefit-shelf tints were the ones that never
/// got the same treatment, and they are also the ones drawn as a 14% wash,
/// which is the worst case: the background moves with the mode, so a single
/// fixed hue is guaranteed to be wrong at one end.
public struct BrandTint: Sendable, Equatable, Hashable {

    public let light: TintRGB
    public let dark: TintRGB

    public init(light: UInt32, dark: UInt32) {
        self.light = TintRGB(hex: light)
        self.dark = TintRGB(hex: dark)
    }

    public func value(for style: InterfaceStyle) -> TintRGB {
        switch style {
        case .light: return light
        case .dark: return dark
        }
    }

    /// The value for a **solid fill with a white glyph on it** — a map pin,
    /// not an icon square.
    ///
    /// **Always the light-mode value, in both modes, and that is not a bug.**
    /// The two roles pull in opposite directions. A 14% wash needs the tint to
    /// contrast with a background that follows the interface style, so it must
    /// move with it. A solid pin is its own background, and the thing that has
    /// to stay readable is the white symbol punched out of it — which needs
    /// the *darker* of the two values whatever the phone's mode is. Feeding
    /// the mode-adaptive value to a pin is how the map ended up with white
    /// glyphs on Success Green at 2.54:1.
    public var solid: TintRGB { light }

    /// The wash this tint paints when it is the background of an icon square.
    public func wash(for style: InterfaceStyle) -> TintRGB {
        value(for: style).blended(alpha: Surface.washAlpha, over: Surface.panel(for: style))
    }

    /// How legible the glyph is against its own icon square.
    public func washContrast(for style: InterfaceStyle) -> Double {
        value(for: style).contrastRatio(against: wash(for: style))
    }

    /// How legible a white glyph is on a solid fill of this tint.
    public var solidContrast: Double {
        TintRGB.white.contrastRatio(against: solid)
    }
}

/// The surfaces these tints are actually drawn on.
///
/// Measured off the CI screenshots rather than guessed: `Assets.xcassets` does
/// not own these, UIKit does, and the only honest way to know what
/// `secondarySystemGroupedBackground` resolves to is to photograph it. If
/// Apple moves either value, the screenshots move with it and these numbers
/// want re-reading.
public enum Surface {

    /// What `CategoryIcon` fills its rounded square with.
    public static let washAlpha: Double = 0.14

    /// `secondarySystemGroupedBackground` — the panel a category icon sits on.
    public static func panel(for style: InterfaceStyle) -> TintRGB {
        switch style {
        case .light: return TintRGB(hex: 0xFFFFFF)
        case .dark: return TintRGB(hex: 0x1C1C1E)
        }
    }
}

// MARK: - The shelf palette

public extension BenefitGroup {

    /// The colour this shelf wears, by day and by night.
    ///
    /// **Every value here clears 3:1 against its own icon square in both
    /// modes, and `BrandTintTests` fails the build if one stops.** Where the
    /// brand sheet's hex already cleared it, the sheet's hex is what is here;
    /// six of the twenty values had to move, and they moved along lightness
    /// only, so the hue a person recognises is the hue the sheet names.
    ///
    /// **Two deliberate departures from the palette sheet, both flagged:**
    ///
    /// - **Drugstores was Error Red** (`#EF4444`), the same colour the sheet
    ///   reserves for "errors, critical alerts, and destructive actions". It
    ///   was being used to say "your best rate here is 3%", which is good
    ///   news rendered in the app's one colour for bad news. It is now a rose
    ///   that is clearly not that red.
    /// - **Card perks was Primary Navy**, which is the header gradient — the
    ///   app's own frame, borrowed as one shelf among ten. Lightening it for
    ///   dark mode produced a blue sitting ΔE 4.7 from Dining's, which is
    ///   close enough to be indistinguishable at icon size. It has its own
    ///   hue now, and Navy goes back to meaning only "this is CardWise".
    var tintPalette: BrandTint {
        switch self {
        case .dining:            return BrandTint(light: 0x1E56D6, dark: 0x4777E5)
        case .groceries:         return BrandTint(light: 0x0C8D63, dark: 0x10B981)
        case .gas:               return BrandTint(light: 0x8B5CF6, dark: 0x8B5CF6)
        case .travel:            return BrandTint(light: 0x3B82F6, dark: 0x3B82F6)
        case .entertainment:     return BrandTint(light: 0x0F8B7E, dark: 0x14B8A6)
        case .drugstores:        return BrandTint(light: 0xE11D48, dark: 0xE11D48)
        case .shopping:          return BrandTint(light: 0xCE5705, dark: 0xF97316)
        case .everydaySpending:  return BrandTint(light: 0x64748B, dark: 0x64748B)
        case .cardPerks:         return BrandTint(light: 0x8B1D6E, dark: 0xDB57B8)
        case .creditsAndBonuses: return BrandTint(light: 0xAD6F07, dark: 0xF59E0B)
        }
    }
}

public extension SpendingCategory {
    /// Borrowed from the shelf it belongs to, so a category and its group are
    /// never two different colours for the same thing.
    var tintPalette: BrandTint { BenefitGroup.containing(self).tintPalette }
}

/// The colours the app's chrome is made of, kept here only so a test can say
/// a shelf is not wearing one of them.
public enum BrandChrome {
    /// Primary Navy — the top of the header gradient.
    public static let navy = TintRGB(hex: 0x0B1F44)
    /// Error Red — errors, critical alerts, destructive actions.
    public static let error = TintRGB(hex: 0xEF4444)
}
