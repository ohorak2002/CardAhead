import Foundation

/// Where a piece of card artwork came from, and therefore whether we are
/// allowed to draw it.
///
/// Issuer card faces are trademarked. Apple Wallet can show the real Amex
/// front because Amex hands Apple that image during provisioning — it is a
/// business relationship, not a download. So every asset in this library has
/// to say where it came from, and anything that cannot answer is refused.
public enum ArtLicence: Codable, Hashable, Sendable {
    /// The issuer sent us the file, or published it in a brand kit we accepted.
    case issuerProvided(source: String, reference: String)
    /// An affiliate or card-marketing programme whose terms cover display.
    case affiliateProgramme(name: String, termsURL: String)
    /// The user photographed their own card. Always fine — it is their card.
    case userPhoto

    /// The one question that matters at draw time.
    public var permitsDisplay: Bool {
        switch self {
        case .issuerProvided, .affiliateProgramme, .userPhoto: return true
        }
    }

    public var attribution: String? {
        switch self {
        case .issuerProvided(let source, let reference):
            return "Artwork supplied by \(source) (\(reference))"
        case .affiliateProgramme(let name, _):
            return "Artwork used under the \(name) programme"
        case .userPhoto:
            return nil
        }
    }
}

/// One licensed card face.
public struct CardArtAsset: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var issuer: String
    public var cardName: String
    /// Name of the image in the app's asset catalog.
    public var imageName: String
    public var licence: ArtLicence
    /// When the grant has to be re-checked. Brand kits get withdrawn.
    public var reviewBy: Date?

    public init(
        id: String,
        issuer: String,
        cardName: String,
        imageName: String,
        licence: ArtLicence,
        reviewBy: Date? = nil
    ) {
        self.id = id
        self.issuer = issuer
        self.cardName = cardName
        self.imageName = imageName
        self.licence = licence
        self.reviewBy = reviewBy
    }

    public func isUsable(asOf date: Date = Date()) -> Bool {
        guard licence.permitsDisplay else { return false }
        if let reviewBy, date > reviewBy { return false }
        return true
    }
}

/// The registry of issuer artwork we are licensed to draw.
///
/// **It ships empty, and that is correct.** Adding a file here is a legal
/// decision, not a design one — see `docs/card-art.md` for what has to be true
/// before an entry goes in. The app degrades gracefully without it: a licensed
/// face if we have one, else the user's own photo, else the drawn finish.
public enum CardArtLibrary {

    /// Populate only with artwork whose licence you can produce on request.
    public static let assets: [CardArtAsset] = []

    /// The only supported way to reach an asset. Anything unlicensed, or past
    /// its review date, is refused here rather than at the call site — so a
    /// forgotten check cannot put unlicensed art on screen.
    public static func asset(
        issuer: String,
        cardName: String,
        asOf date: Date = Date()
    ) -> CardArtAsset? {
        let wantedIssuer = issuer.lowercased()
        let wantedName = cardName.lowercased()
        return assets.first {
            $0.issuer.lowercased() == wantedIssuer
                && $0.cardName.lowercased() == wantedName
                && $0.isUsable(asOf: date)
        }
    }

    /// Entries that have gone stale and need the grant re-confirmed.
    public static func needingReview(asOf date: Date = Date()) -> [CardArtAsset] {
        assets.filter { asset in
            guard let reviewBy = asset.reviewBy else { return false }
            return date > reviewBy
        }
    }

    /// Shown in Settings so the licensing position is visible rather than folklore.
    public static var attributions: [String] {
        assets.compactMap(\.licence.attribution).sorted()
    }
}

/// How a card's face should be drawn, in priority order.
public enum CardArtSource: Hashable, Sendable {
    case licensed(CardArtAsset)
    case userPhoto(String)
    case drawn

    /// Licensed art first, then the user's own photo, then the drawn finish.
    public static func resolve(for card: Card, asOf date: Date = Date()) -> CardArtSource {
        if let asset = CardArtLibrary.asset(issuer: card.issuer, cardName: card.name, asOf: date) {
            return .licensed(asset)
        }
        if let filename = card.photoFilename {
            return .userPhoto(filename)
        }
        return .drawn
    }
}
