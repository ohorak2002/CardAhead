import Foundation

/// A photograph of a real business, as the provider describes it.
///
/// **What this is not: an image.** `CardKit` has no idea what a `UIImage` is
/// and is not going to learn — it describes the request, the app performs it,
/// exactly like `HTTPRequest`. What lives here is the part worth testing on
/// Linux: which resource to ask for, how big to ask for it, and the credit
/// that has to appear next to it.
///
/// **Why the app shows these at all, when the map deliberately did not.** The
/// earlier note on `PlaceRow` argued a category tile was doing the picture's
/// job — it names the kind of shop, costs nothing, and matches the pin. That
/// was true about *categorisation* and wrong about *recognition*. A blue fork
/// says "restaurant"; a photograph says "the one on the corner you walked past
/// this morning", and that is the difference between a list of search results
/// and a list of places. The costs the old note raised are real and are
/// handled rather than denied — see `PlacePhotoUse` for the sizing and
/// `docs/places-api.md` for the billing.
public struct PlacePhoto: Codable, Hashable, Sendable {

    /// The provider's opaque handle for this image, e.g.
    /// `places/ChIJ.../photos/AeJbb3...`. Meaningless on its own and not
    /// parsed anywhere: it is a token to hand back, and Google reserves the
    /// right to change its shape.
    public var name: String

    /// The image's own size, when the provider stated it. Used only to avoid
    /// asking for more pixels than exist — see `pixelWidth(for:)`. Absent is
    /// ordinary and costs nothing but a slightly larger request.
    public var widthPx: Int?
    public var heightPx: Int?

    /// Who took the photograph.
    ///
    /// **Not decoration and not optional in spirit.** Google's terms require
    /// showing the attributions supplied with a photo wherever that photo is
    /// shown. The app satisfies that on the place detail, where the credit can
    /// be read; a 96-point row thumbnail cannot carry a legible credit, which
    /// is a reason to keep the full-size photo one tap away rather than a
    /// reason to drop the credit.
    public var attributions: [String]

    public init(
        name: String,
        widthPx: Int? = nil,
        heightPx: Int? = nil,
        attributions: [String] = []
    ) {
        self.name = name
        self.widthPx = widthPx
        self.heightPx = heightPx
        self.attributions = attributions
    }

    /// "Photo by Jane Doe", or the first credit and a count when there are
    /// several. Nil when the provider named nobody, which is common for
    /// business-supplied images.
    public var attributionText: String? {
        guard let first = attributions.first else { return nil }
        if attributions.count == 1 { return "Photo by \(first)" }
        return "Photo by \(first) and \(attributions.count - 1) more"
    }

    /// How many pixels wide to ask for, for a given use.
    ///
    /// Clamped by the photo's own width so a 400-pixel original is never
    /// requested at 1080: the provider would upscale it, the bytes would cost
    /// the same as a real 1080 image, and the result would be blurrier than
    /// asking honestly.
    public func pixelWidth(for use: PlacePhotoUse) -> Int {
        guard let widthPx, widthPx > 0 else { return use.pixelWidth }
        return min(use.pixelWidth, widthPx)
    }

    public func pixelHeight(for use: PlacePhotoUse) -> Int {
        guard let heightPx, heightPx > 0 else { return use.pixelHeight }
        return min(use.pixelHeight, heightPx)
    }

    /// The cache key for this photo at this size.
    ///
    /// The size is part of the key because a row thumbnail and a detail hero
    /// are different downloads of the same photograph, and a cache that
    /// confused them would either serve a thumbnail into a full-width hero or
    /// hold a 1080-pixel image to draw 96 points of it.
    ///
    /// Hashed rather than used raw: the name is long, contains `/`, and would
    /// otherwise become a path.
    public func cacheKey(for use: PlacePhotoUse) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in name.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 36) + "-" + use.rawValue
    }
}

/// Where a place photo is about to be drawn, which is the only thing that
/// decides how many pixels to buy.
///
/// **Three sizes, not a free-form number.** Every caller passing its own point
/// size means the same photograph downloaded at forty slightly different
/// widths across the app, each a separate billed request and a separate cache
/// entry, none of them reusable. Three buckets means the row thumbnail you
/// scrolled past is still in the cache when you scroll back.
public enum PlacePhotoUse: String, CaseIterable, Sendable {

    /// A thumbnail beside a name in a list. Drawn at about 88 points square.
    case row

    /// The photograph on a place card — the strip across the top of the map's
    /// bottom sheet, or a recommendation. Full screen width, shallow.
    case card

    /// The top of the place detail, the largest this app ever draws one.
    case hero

    /// Sized for a 3x display, which is what every phone the app supports has
    /// — asking for 1x and letting the phone stretch it is the single most
    /// visible way an image looks cheap.
    public var pixelWidth: Int {
        switch self {
        case .row: return 264
        case .card: return 1_170
        case .hero: return 1_170
        }
    }

    public var pixelHeight: Int {
        switch self {
        case .row: return 264
        case .card: return 540
        case .hero: return 780
        }
    }

    /// How long the bytes may be kept.
    ///
    /// Google's terms allow caching this content for a limited period rather
    /// than indefinitely, and 30 days is the figure that applies. It is also
    /// the right number on its own merits: a shop's photograph does not change
    /// week to week, and the alternative is paying for the same image every
    /// time somebody opens the map.
    public static let cacheLifetime: TimeInterval = 60 * 60 * 24 * 30
}
