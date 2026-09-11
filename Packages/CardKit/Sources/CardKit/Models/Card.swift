import Foundation

/// A caveat attached to a category, surfaced in the card detail view and in the
/// notification body when it applies. This is where merchant-coding reality lives:
/// Costco does not code as a grocery store, and a gas station with a big
/// convenience store may code as either.
public struct CategoryNote: Codable, Hashable, Sendable, Identifiable {
    public var id: String { "\(category.rawValue)|\(text)" }
    public var category: SpendingCategory
    public var text: String

    public init(category: SpendingCategory, text: String) {
        self.category = category
        self.text = text
    }
}

public struct Card: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var issuer: String
    public var name: String
    public var currency: RewardCurrency
    public var rules: [CategoryRule]
    public var rotatingProgram: RotatingProgram?
    public var perks: [Perk]
    public var welcomeBonus: WelcomeBonus?
    public var notes: [CategoryNote]
    /// Percentage taken off every purchase made in a foreign currency.
    /// Real money, so the engine subtracts it when the user is abroad.
    public var foreignTransactionFeePercent: Double
    public var annualFeeDollars: Money
    /// The user's manual thumb on the scale. Only breaks ties.
    public var isPinned: Bool
    /// Key into the app's card art palette. See `CardArt`.
    public var artKey: String
    /// Optional on purpose: a wallet saved before finishes existed decodes as
    /// nil rather than failing the whole file. Read it through `appearance`.
    public var finish: CardFinish?
    /// Filename of a photo the user took of their own card, stored alongside
    /// the wallet. We cannot ship the banks' artwork — it is theirs — so a
    /// photo of the card in your own hand is the only route to an exact match.
    public var photoFilename: String?
    /// Which catalog product this card is, when the user picked it from the
    /// list rather than describing one by hand.
    ///
    /// Optional, and nil for a card typed in manually. It is what lets the app
    /// say where these rates came from and when somebody last checked them,
    /// offer "change card" without a form, and one day match the card against
    /// a licensed image. A wallet file written before this field existed still
    /// decodes — those cards simply have no product behind them.
    public var catalogProductID: String?

    public init(
        id: UUID = UUID(),
        issuer: String,
        name: String,
        currency: RewardCurrency = .cashBack,
        rules: [CategoryRule] = [],
        rotatingProgram: RotatingProgram? = nil,
        perks: [Perk] = [],
        welcomeBonus: WelcomeBonus? = nil,
        notes: [CategoryNote] = [],
        foreignTransactionFeePercent: Double = 0,
        annualFeeDollars: Money = 0,
        isPinned: Bool = false,
        artKey: String = "slate",
        finish: CardFinish? = nil,
        photoFilename: String? = nil,
        catalogProductID: String? = nil
    ) {
        self.id = id
        self.issuer = issuer
        self.name = name
        self.currency = currency
        self.rules = rules
        self.rotatingProgram = rotatingProgram
        self.perks = perks
        self.welcomeBonus = welcomeBonus
        self.notes = notes
        self.foreignTransactionFeePercent = foreignTransactionFeePercent
        self.annualFeeDollars = annualFeeDollars
        self.isPinned = isPinned
        self.artKey = artKey
        self.finish = finish
        self.photoFilename = photoFilename
        self.catalogProductID = catalogProductID
    }

    /// True when these rates came out of the catalog rather than off the top of
    /// somebody's head. The Benefits screen shows a source and a date for one
    /// and offers a manual editor for the other.
    public var isCatalogCard: Bool { catalogProductID != nil }

    /// This product, standing where another card stood in the wallet.
    ///
    /// "I picked the wrong card" must not cost somebody their place in the
    /// stack, the star they put on it, or the photo they took of the real thing
    /// in their hand. Those belong to the slot and to the person; everything the
    /// catalog asserts — the rates, the fees, the perks, the product it is —
    /// comes from the card replacing it.
    public func takingWalletPlace(of previous: Card) -> Card {
        var card = self
        card.id = previous.id
        card.isPinned = previous.isPinned
        card.photoFilename = previous.photoFilename
        return card
    }

    /// The finish to draw with. Matte is the safe default for a card whose
    /// material the user never told us about.
    public var appearance: CardFinish { finish ?? .matte }

    public var displayName: String { "\(issuer) \(name)" }

    public func rule(for category: SpendingCategory) -> CategoryRule? {
        rules.first { $0.category == category }
    }

    public var baseRate: Double {
        rule(for: .base)?.rate ?? 1.0
    }

    public func notes(for category: SpendingCategory) -> [CategoryNote] {
        notes.filter { $0.category == category }
    }

    public var travelPerks: [Perk] {
        perks.filter(\.isTravelRelevant)
    }

    /// Every category this card pays a bonus on, including the current
    /// rotating quarter. Drives the expanded card view.
    public func bonusCategories(asOf date: Date = Date()) -> [SpendingCategory] {
        var found = rules.filter { $0.category != .base && $0.rate > baseRate }.map(\.category)
        if let rotating = rotatingProgram,
           let quarter = rotating.quarter(Quarter.containing(date)) {
            found.append(contentsOf: quarter.categories)
        }
        return Array(Set(found)).sorted { $0.displayName < $1.displayName }
    }
}
