import Foundation

/// Where a piece of card artwork came from.
///
/// Issuer card faces are trademarked. Apple Wallet can show the real Amex
/// front because Amex hands Apple that image during provisioning — it is a
/// business relationship, not a download. So every asset in this library has
/// to say where it came from, and anything that cannot answer is refused.
///
/// This says *where it came from*. Whether we may draw it today is a separate
/// question with a separate answer: see `ArtLicenceStatus` and `ArtUse`.
/// Keeping the three apart is the whole point — provenance does not expire,
/// permission does, and permission for one place is not permission everywhere.
public enum ArtLicence: Codable, Hashable, Sendable {
    /// The issuer sent us the file, or published it in a brand kit we accepted.
    case issuerProvided(source: String, reference: String)
    /// An affiliate or card-marketing programme whose terms cover display.
    case affiliateProgramme(name: String, termsURL: String)
    /// The user photographed their own card. Always fine — it is their card.
    case userPhoto

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

    /// Who to go back to when the grant needs re-confirming.
    public var reference: String? {
        switch self {
        case .issuerProvided(let source, let reference): return "\(source) — \(reference)"
        case .affiliateProgramme(let name, let termsURL): return "\(name) — \(termsURL)"
        case .userPhoto: return nil
        }
    }
}

/// What state a grant is in right now, as a fact somebody wrote down.
///
/// Note what is deliberately **not** a case here: `expired`. Expiry is date
/// arithmetic, not a state a human remembers to update — a stored `.expired`
/// would be wrong on the day it lapsed and stay wrong until someone noticed.
/// `CardArtAsset.isUsable(for:asOf:)` works it out from the dates instead.
///
/// The default everywhere is `pendingReview`, and that is load-bearing. A
/// manifest that forgot to say, a field that failed to decode, an entry
/// somebody half-wrote — all of them land on "not yet", never on "approved".
public enum ArtLicenceStatus: String, Codable, Hashable, Sendable, CaseIterable {
    /// Asked for, or being negotiated. The commonest state by far, and the one
    /// that must never draw.
    case pendingReview
    /// Granted in writing, and the writing is somewhere we can produce it.
    case approved
    /// Granted once, withdrawn since. Kept rather than deleted so the history
    /// survives and nobody cheerfully re-adds it next quarter.
    case revoked

    /// The one question that matters at draw time.
    public var permitsDisplay: Bool { self == .approved }

    public var displayName: String {
        switch self {
        case .pendingReview: return "Pending"
        case .approved: return "Approved"
        case .revoked: return "Revoked"
        }
    }
}

/// What a grant actually covers.
///
/// Permission to put an image inside the app is **not** permission to put it
/// on the App Store listing, a website hero, or a pitch deck. Brand kits
/// routinely grant one and withhold the other, and conflating them is the
/// easiest way to turn a real licence into a real problem. So each use is
/// asked for separately and the asset says which it holds.
public enum ArtUse: String, Codable, Hashable, Sendable, CaseIterable {
    /// Drawn as the user's own card, in their wallet. What this app needs.
    case walletDisplay
    /// Anywhere else inside the app — a picker row, a preview, a notification.
    case appDisplay
    /// Website, social, advertising, press, decks. Outward-facing.
    case marketing
    /// App Store screenshots and the preview video. Apple's reviewers look at
    /// these, and they are the most commonly withheld of the four.
    case appStore

    public var displayName: String {
        switch self {
        case .walletDisplay: return "In the wallet"
        case .appDisplay: return "Elsewhere in the app"
        case .marketing: return "Marketing"
        case .appStore: return "App Store listing"
        }
    }

    /// The same thing said as a phrase, so a refusal reads as a sentence
    /// rather than a label welded onto one.
    public var auditPhrase: String {
        switch self {
        case .walletDisplay: return "showing it in the wallet"
        case .appDisplay: return "showing it elsewhere in the app"
        case .marketing: return "marketing"
        case .appStore: return "the App Store listing"
        }
    }
}

/// One licensed card face, and the paper trail that allows it on screen.
///
/// Every field exists to answer a question somebody will ask later: which
/// product is this, which printing of it, who said yes, where is that in
/// writing, from when until when, and for what. An asset that cannot answer
/// does not draw.
public struct CardArtAsset: Identifiable, Codable, Hashable, Sendable {
    public var id: String

    /// The stable catalog product this artwork is *of* — `amex-gold`, not
    /// "Amex Gold". Names change; `CatalogEntry.productID` does not, which is
    /// exactly why the catalog has them and why the lookup keys on this rather
    /// than on two display strings that could collide with a hand-typed card.
    public var productID: String

    /// Human labels, for the audit list and the credit line. Never the key.
    public var issuer: String
    public var cardName: String

    /// Which printing of the card this is. Issuers redesign; when they do, the
    /// new face arrives as a second asset with a later version rather than
    /// overwriting the one a grant was written against.
    public var assetVersion: String

    /// Name of the image in the app's asset catalog.
    public var imageName: String

    public var licence: ArtLicence
    /// Defaults to `.pendingReview` on purpose. Silence is never consent.
    public var status: ArtLicenceStatus
    /// Empty by default, for the same reason.
    public var permittedUses: Set<ArtUse>

    /// From when the grant runs. Nil means "no start stated".
    public var effectiveDate: Date?
    /// When it lapses, or when it has to be re-confirmed. Nil means no end
    /// date was given — which is rarer than it sounds and worth chasing.
    public var expiresOn: Date?

    /// Whether we may recolour, overlay, or otherwise alter the file.
    public var modificationAllowed: Bool
    /// Whether we may crop it — separate from modification, because a card
    /// face cropped to a thumbnail is the single most common thing an app
    /// does to one, and plenty of grants forbid exactly that.
    public var croppingAllowed: Bool

    /// Where the grant applies. Nil means it was not restricted.
    public var territory: String?
    /// Some grants require a visible credit line. Showing it always is simpler
    /// than tracking which, so this defaults to true.
    public var attributionRequired: Bool

    public init(
        id: String,
        productID: String,
        issuer: String,
        cardName: String,
        assetVersion: String = "1",
        imageName: String,
        licence: ArtLicence,
        status: ArtLicenceStatus = .pendingReview,
        permittedUses: Set<ArtUse> = [],
        effectiveDate: Date? = nil,
        expiresOn: Date? = nil,
        modificationAllowed: Bool = false,
        croppingAllowed: Bool = false,
        territory: String? = nil,
        attributionRequired: Bool = true
    ) {
        self.id = id
        self.productID = productID
        self.issuer = issuer
        self.cardName = cardName
        self.assetVersion = assetVersion
        self.imageName = imageName
        self.licence = licence
        self.status = status
        self.permittedUses = permittedUses
        self.effectiveDate = effectiveDate
        self.expiresOn = expiresOn
        self.modificationAllowed = modificationAllowed
        self.croppingAllowed = croppingAllowed
        self.territory = territory
        self.attributionRequired = attributionRequired
    }

    /// The single gate. Everything that draws issuer artwork goes through it.
    ///
    /// Four independent ways to say no, and the order does not matter because
    /// any one of them is enough.
    public func isUsable(for use: ArtUse = .walletDisplay, asOf date: Date = Date()) -> Bool {
        guard status.permitsDisplay else { return false }
        guard permittedUses.contains(use) else { return false }
        if let effectiveDate, date < effectiveDate { return false }
        if let expiresOn, date > expiresOn { return false }
        return true
    }

    /// Lapsed, as opposed to never granted. Drives the audit list.
    public func hasExpired(asOf date: Date = Date()) -> Bool {
        guard let expiresOn else { return false }
        return date > expiresOn
    }

    /// Granted, but not yet. Also drives the audit list.
    public func isNotYetEffective(asOf date: Date = Date()) -> Bool {
        guard let effectiveDate else { return false }
        return date < effectiveDate
    }

    /// One line saying why this asset is not on screen, for the internal audit
    /// view. Nil when it is perfectly fine.
    public func blockingReason(for use: ArtUse = .walletDisplay, asOf date: Date = Date()) -> String? {
        if !status.permitsDisplay {
            switch status {
            case .pendingReview: return "Grant not confirmed yet"
            case .revoked: return "Grant was withdrawn"
            case .approved: return nil
            }
        }
        if isNotYetEffective(asOf: date) { return "Grant has not started yet" }
        if hasExpired(asOf: date) { return "Grant lapsed and needs re-confirming" }
        if !permittedUses.contains(use) { return "Grant does not cover \(use.auditPhrase)" }
        return nil
    }

    // MARK: - Decoding

    /// Written out by hand rather than synthesised, and this is the reason:
    /// a manifest missing `status` must decode as `.pendingReview`, and one
    /// missing `permittedUses` as none at all. The synthesised initialiser
    /// would throw on the first and — worse, if these were made optional with
    /// permissive defaults — could let a half-written file read as a grant.
    /// Fail towards "no", never towards "yes".
    private enum CodingKeys: String, CodingKey {
        case id, productID, issuer, cardName, assetVersion, imageName
        case licence, status, permittedUses, effectiveDate, expiresOn
        case modificationAllowed, croppingAllowed, territory, attributionRequired
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        productID = try container.decode(String.self, forKey: .productID)
        issuer = try container.decode(String.self, forKey: .issuer)
        cardName = try container.decode(String.self, forKey: .cardName)
        assetVersion = try container.decodeIfPresent(String.self, forKey: .assetVersion) ?? "1"
        imageName = try container.decode(String.self, forKey: .imageName)
        licence = try container.decode(ArtLicence.self, forKey: .licence)
        status = try container.decodeIfPresent(ArtLicenceStatus.self, forKey: .status) ?? .pendingReview
        permittedUses = try container.decodeIfPresent(Set<ArtUse>.self, forKey: .permittedUses) ?? []
        effectiveDate = try container.decodeIfPresent(Date.self, forKey: .effectiveDate)
        expiresOn = try container.decodeIfPresent(Date.self, forKey: .expiresOn)
        modificationAllowed = try container.decodeIfPresent(Bool.self, forKey: .modificationAllowed) ?? false
        croppingAllowed = try container.decodeIfPresent(Bool.self, forKey: .croppingAllowed) ?? false
        territory = try container.decodeIfPresent(String.self, forKey: .territory)
        attributionRequired = try container.decodeIfPresent(Bool.self, forKey: .attributionRequired) ?? true
    }

    /// Reads one `license.json`. Returns nil rather than throwing, because
    /// every caller's correct response to a broken manifest is identical: draw
    /// the card ourselves and carry on.
    public static func fromManifest(_ data: Data) -> CardArtAsset? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CardArtAsset.self, from: data)
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

    // MARK: - The only supported way in

    /// Artwork for a card in somebody's wallet.
    ///
    /// Keyed on the catalog product ID, never on the issuer and name strings.
    /// A card typed in by hand has no product ID and therefore never matches —
    /// which is the safe answer, because "Amex"/"Gold" typed into a form is
    /// not evidence that somebody holds the product a grant was written for.
    public static func asset(
        for card: Card,
        use: ArtUse = .walletDisplay,
        asOf date: Date = Date()
    ) -> CardArtAsset? {
        guard let productID = card.catalogProductID else { return nil }
        return asset(productID: productID, use: use, asOf: date)
    }

    /// The refusal lives here rather than at each call site, so a forgotten
    /// check in a new view cannot put unlicensed art on screen.
    public static func asset(
        productID: String,
        use: ArtUse = .walletDisplay,
        asOf date: Date = Date()
    ) -> CardArtAsset? {
        match(productID: productID, in: assets, use: use, asOf: date)
    }

    /// The matching rule itself, against a list handed in.
    ///
    /// It exists because `assets` ships empty and must stay that way, which
    /// would otherwise leave every rule below it — the expiry, the revocation,
    /// the use check, which version wins — permanently untested. Tests pass
    /// their own list; production passes `assets` and nothing else can, because
    /// this is internal. A public overload here would be a way around the
    /// registry, which is the one thing this file exists to prevent.
    static func match(
        productID: String,
        in assets: [CardArtAsset],
        use: ArtUse = .walletDisplay,
        asOf date: Date = Date()
    ) -> CardArtAsset? {
        assets
            .filter { $0.productID == productID && $0.isUsable(for: use, asOf: date) }
            // Newest printing of the card wins when an issuer has redesigned
            // and both grants are live.
            .max { $0.assetVersion < $1.assetVersion }
    }

    // MARK: - Audit

    /// Every entry that is not currently drawable, with the reason. This is
    /// the internal view's whole data source, and it is deliberately the same
    /// gate the drawing path uses rather than a second opinion about it.
    public static func blocked(
        for use: ArtUse = .walletDisplay,
        asOf date: Date = Date()
    ) -> [BlockedAsset] {
        assets.compactMap { asset in
            guard let reason = asset.blockingReason(for: use, asOf: date) else { return nil }
            return BlockedAsset(asset: asset, reason: reason)
        }
    }

    /// An asset and why it is not on screen. A struct rather than a tuple so
    /// it can carry an id into a SwiftUI list.
    public struct BlockedAsset: Identifiable, Hashable, Sendable {
        public var id: String { asset.id }
        public var asset: CardArtAsset
        public var reason: String

        public init(asset: CardArtAsset, reason: String) {
            self.asset = asset
            self.reason = reason
        }
    }

    /// Entries whose grant has lapsed and needs the paperwork chasing again.
    public static func needingReview(asOf date: Date = Date()) -> [CardArtAsset] {
        assets.filter { $0.hasExpired(asOf: date) }
    }

    /// Shown in Settings so the licensing position is visible rather than
    /// folklore. Only lists artwork actually on screen — a revoked grant must
    /// not leave a credit line behind claiming we still have it.
    public static func attributions(asOf date: Date = Date()) -> [String] {
        assets
            .filter { $0.isUsable(asOf: date) && $0.attributionRequired }
            .compactMap(\.licence.attribution)
            .sorted()
    }
}

/// How a card's face should be drawn, in priority order.
public enum CardArtSource: Hashable, Sendable {
    case licensed(CardArtAsset)
    case userPhoto(String)
    case drawn

    /// Licensed art first, then the user's own photo, then the drawn finish.
    ///
    /// Never reverse this. A grant we hold is the exact thing; a photo is the
    /// user's own card and always theirs to show; the drawn face is ours and
    /// always available, which is why nothing below it is needed.
    public static func resolve(
        for card: Card,
        use: ArtUse = .walletDisplay,
        asOf date: Date = Date()
    ) -> CardArtSource {
        resolve(for: card, in: CardArtLibrary.assets, use: use, asOf: date)
    }

    /// The same three-step decision against a list handed in, so the order can
    /// be tested with a licensed asset actually present. Internal, for the
    /// reason given on `CardArtLibrary.match`.
    static func resolve(
        for card: Card,
        in assets: [CardArtAsset],
        use: ArtUse = .walletDisplay,
        asOf date: Date = Date()
    ) -> CardArtSource {
        if let productID = card.catalogProductID,
           let asset = CardArtLibrary.match(productID: productID, in: assets, use: use, asOf: date) {
            return .licensed(asset)
        }
        if let filename = card.photoFilename, !filename.isEmpty {
            return .userPhoto(filename)
        }
        return .drawn
    }

    /// What the app is allowed to say about this face out loud.
    ///
    /// Lives here rather than in a view because it is a claim about provenance,
    /// and a claim about provenance should be testable. The drawn case must
    /// never imply the bank had anything to do with it.
    public var provenanceLine: String {
        switch self {
        case .licensed(let asset):
            return asset.licence.attribution ?? "Artwork used with the issuer's permission."
        case .userPhoto:
            return "Your own photo of this card."
        case .drawn:
            return "Drawn by CardWise. Not the bank's artwork — we show that only where we have permission to."
        }
    }

    /// The short label, for a row that has no room for the sentence.
    public var shortLabel: String {
        switch self {
        case .licensed: return "Official card artwork"
        case .userPhoto: return "Your card photo"
        case .drawn: return "CardWise representation"
        }
    }

    /// What VoiceOver should call this card, given where its face came from.
    /// "Blue rectangle" is what happens when nobody writes this function.
    public func accessibilityDescription(for card: Card) -> String {
        switch self {
        case .licensed: return "\(card.displayName) card"
        case .userPhoto: return "Photo of your \(card.displayName) card"
        case .drawn: return "CardWise representation of \(card.displayName)"
        }
    }
}
