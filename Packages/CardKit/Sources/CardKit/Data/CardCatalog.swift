import Foundation

/// One card product in the seed database: which product it is, what it earns,
/// where its numbers came from and when somebody last looked.
///
/// Rates, caps and annual fees are facts about somebody else's product that
/// change without telling us. A catalog that states them without saying when it
/// last checked is a catalog that quietly becomes wrong, and nobody can tell
/// which parts. So every entry carries the issuer's own page and a date, and
/// the app shows both.
public struct CatalogEntry: Identifiable, Sendable {
    /// Stable for the life of the product, and the thing a saved card points
    /// back at. The display name is not: issuers rename cards, and a wallet
    /// that identified a card by its name would lose track of it the day they
    /// did. Lower case, hyphenated, issuer first.
    public var id: String { productID }
    public var productID: String

    /// The card itself. Stamped with `productID` on the way in, so a card that
    /// came out of the catalog can always be traced back to its entry.
    public private(set) var card: Card

    public var network: CardNetwork
    /// Personal or business. "Gold Card" is two different products.
    public var variant: CardVariant

    /// What the bank calls itself when it is not squeezing the name onto a
    /// card. `Card.issuer` holds "Amex" because that is what fits; somebody
    /// searching types "American Express".
    public var issuerFullName: String

    /// Every other name a person might reasonably type for this card.
    /// Nicknames, the issuer's full product name, common abbreviations.
    public var aliases: [String]

    /// The issuer's own terms page. Never a review site: those are downstream
    /// of the same drift this field exists to catch.
    public var termsURL: String
    /// When a human last read that page against these numbers.
    public var checkedOn: Date
    /// True things about this card the model cannot express. Written down
    /// rather than approximated, because an approximation reads as a fact.
    public var notModelled: [String]

    public init(
        productID: String,
        card: Card,
        network: CardNetwork,
        variant: CardVariant = .personal,
        issuerFullName: String? = nil,
        aliases: [String] = [],
        termsURL: String,
        checkedOn: Date,
        notModelled: [String] = []
    ) {
        self.productID = productID
        var stamped = card
        stamped.catalogProductID = productID
        self.card = stamped
        self.network = network
        self.variant = variant
        self.issuerFullName = issuerFullName ?? card.issuer
        self.aliases = aliases
        self.termsURL = termsURL
        self.checkedOn = checkedOn
        self.notModelled = notModelled
    }

    /// Card terms move a few times a year. Past this, the app stops presenting
    /// these numbers as current.
    public static let freshnessWindow: TimeInterval = 60 * 60 * 24 * 180

    public func isStale(asOf date: Date = Date()) -> Bool {
        date.timeIntervalSince(checkedOn) > Self.freshnessWindow
    }

    /// Everything a search should look through: the short issuer and the long
    /// one, the product name, the network, every alias, and "business" when
    /// that is what distinguishes this card from its personal twin.
    var searchText: String {
        var parts = [card.issuer, issuerFullName, card.name, network.displayName]
        parts.append(contentsOf: aliases)
        if variant == .business { parts.append(variant.displayName) }
        return parts.joined(separator: " ").lowercased()
    }

    /// Every word typed has to appear somewhere. "amex gold" finds the Gold
    /// Card; "gold" on its own finds it too, and would find a second gold card
    /// if the catalog held one — which is the point of showing the exact
    /// product name on every row.
    public func matches(_ query: String) -> Bool {
        let words = query.lowercased().split { !$0.isLetter && !$0.isNumber }
        guard !words.isEmpty else { return true }
        let haystack = searchText
        return words.allSatisfy { haystack.contains($0) }
    }
}

/// One bank, as the add-card screen lists them.
public struct CatalogIssuer: Identifiable, Hashable, Sendable {
    public var id: String { name }
    /// Short, as it is printed on the card face and stored on `Card.issuer`.
    public var name: String
    /// What the bank calls itself, and what somebody searching types.
    public var fullName: String
    public var cardCount: Int
}

/// The seed database the add-card flow searches.
///
/// It is a typing shortcut, not a source of truth, and never a starter wallet.
/// Every number below was read off the issuer's own page on the date in the
/// entry; check `CardCatalog.checkedOn` before trusting any of it, and check
/// with the issuer before acting on it.
public enum CardCatalog {

    /// The one day all of this was audited against live issuer terms.
    public static let checkedOn = date(2026, 9, 11)

    public static var entries: [CatalogEntry] {
        [
            chaseFreedomFlexEntry,
            chaseSapphirePreferredEntry,
            discoverItEntry,
            amexBlueCashPreferredEntry,
            amexGoldEntry,
            citiDoubleCashEntry,
            capitalOneSavorEntry,
            wellsFargoActiveCashEntry,
            costcoAnywhereVisaEntry
        ]
    }

    public static var all: [Card] {
        entries.map(\.card)
    }

    // MARK: - Finding a card

    /// The banks, as the first screen of the add-card flow lists them.
    /// Ordered by the name somebody would look for, not the short one.
    public static var issuers: [CatalogIssuer] {
        var order: [String] = []
        var byName: [String: CatalogIssuer] = [:]
        for entry in entries {
            let name = entry.card.issuer
            if var existing = byName[name] {
                existing.cardCount += 1
                byName[name] = existing
            } else {
                order.append(name)
                byName[name] = CatalogIssuer(
                    name: name,
                    fullName: entry.issuerFullName,
                    cardCount: 1
                )
            }
        }
        return order.compactMap { byName[$0] }.sorted { $0.fullName < $1.fullName }
    }

    /// Every product this bank sells, for the second screen.
    public static func entries(issuedBy issuer: String) -> [CatalogEntry] {
        entries.filter { $0.card.issuer == issuer }
    }

    /// The lookup a saved card uses to find its own entry again.
    public static func entry(productID: String) -> CatalogEntry? {
        entries.first { $0.productID == productID }
    }

    /// The entry a card in the wallet came from, if it came from one at all.
    public static func entry(for card: Card) -> CatalogEntry? {
        guard let productID = card.catalogProductID else { return nil }
        return entry(productID: productID)
    }

    public static func entry(named displayName: String) -> CatalogEntry? {
        entries.first { $0.card.displayName == displayName }
    }

    /// Alias-aware. "amex gold", "American Express Gold Card" and "gold card"
    /// all reach the same product; searching the display name alone reached
    /// none of them.
    public static func searchEntries(_ query: String) -> [CatalogEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries }
        return entries.filter { $0.matches(trimmed) }
    }

    public static func search(_ query: String) -> [Card] {
        searchEntries(query).map(\.card)
    }

    // MARK: - Chase

    public static var chaseFreedomFlex: Card { chaseFreedomFlexEntry.card }

    static var chaseFreedomFlexEntry: CatalogEntry {
        CatalogEntry(
            productID: "chase-freedom-flex",
            card: Card(
                issuer: "Chase",
                name: "Freedom Flex",
                currency: .cashBack,
                rules: [
                    CategoryRule(category: .travelPortal, rate: 5, note: "Booked through Chase Travel."),
                    CategoryRule(category: .dining, rate: 3),
                    CategoryRule(category: .drugstores, rate: 3),
                    CategoryRule(category: .base, rate: 1)
                ],
                rotatingProgram: RotatingProgram(
                    rate: 5,
                    cap: EarnCap(limitDollars: 1_500, period: .quarterly),
                    quarters: [
                        RotatingQuarter(
                            quarter: Quarter(year: 2026, index: 3),
                            categories: [.gas, .transit, .entertainment],
                            summary: "Gas stations and EV charging, public transit, select live entertainment, and United Way donations",
                            // Chase closes activation before the quarter ends,
                            // unlike Discover. Missing it costs the whole bonus.
                            activationDeadline: date(2026, 9, 14)
                        )
                    ],
                    knownThrough: Quarter(year: 2026, index: 3),
                    sourceURL: "https://www.chase.com/personal/credit-cards/education/chase-cards/how-to-activate-chase-freedom-flex-rewards-categories"
                ),
                perks: [.purchaseProtection, .extendedWarranty, .cellPhoneProtection],
                foreignTransactionFeePercent: 3,
                annualFeeDollars: 0,
                artKey: "midnight",
                finish: .glossy
            ),
            network: .mastercard,
            aliases: ["Chase Freedom Flex", "Freedom Flex", "Freedom"],
            termsURL: "https://creditcards.chase.com/cash-back-credit-cards/freedom/flex",
            checkedOn: checkedOn,
            notModelled: [
                "Q4 2026 had not been announced when this was checked. Chase publishes about a fortnight before the quarter starts.",
                "United Way donations are part of this quarter's 5%, but a donation is not a shop and nothing here can notice one."
            ]
        )
    }

    public static var chaseSapphirePreferred: Card { chaseSapphirePreferredEntry.card }

    static var chaseSapphirePreferredEntry: CatalogEntry {
        CatalogEntry(
            productID: "chase-sapphire-preferred",
            card: Card(
                issuer: "Chase",
                name: "Sapphire Preferred",
                currency: .ultimateRewards,
                rules: [
                    CategoryRule(category: .travelPortal, rate: 5, note: "Booked through Chase Travel."),
                    CategoryRule(category: .dining, rate: 3),
                    CategoryRule(category: .streaming, rate: 3),
                    CategoryRule(category: .gas, rate: 3, note: "Gas and EV charging."),
                    CategoryRule(category: .travel, rate: 2),
                    CategoryRule(category: .flights, rate: 2),
                    CategoryRule(category: .hotels, rate: 2),
                    CategoryRule(category: .base, rate: 1)
                ],
                perks: [
                    .noForeignTransactionFee,
                    .tripDelayInsurance,
                    .tripCancellationInsurance,
                    .rentalCarCDW,
                    .annualTravelCredit,
                    .purchaseProtection,
                    .extendedWarranty
                ],
                notes: [
                    // The 3x grocery bonus is online-only. This app's whole job
                    // is telling you what to pay with while standing in a shop,
                    // so writing it as a grocery rule would make it confidently
                    // wrong at exactly the moment it speaks.
                    CategoryNote(
                        category: .groceries,
                        text: "The 3x grocery bonus is for online orders only. Paying at the till in the shop earns the base rate."
                    ),
                    CategoryNote(
                        category: .hotels,
                        text: "Vacation homes on Airbnb, Vrbo and similar earn 3x rather than the 2x shown here."
                    )
                ],
                foreignTransactionFeePercent: 0,
                annualFeeDollars: 95,
                artKey: "sapphire",
                finish: .metal
            ),
            network: .visa,
            aliases: ["Chase Sapphire Preferred", "Sapphire Preferred", "CSP", "Sapphire"],
            termsURL: "https://creditcards.chase.com/rewards-credit-cards/sapphire/preferred",
            checkedOn: checkedOn,
            notModelled: [
                "Refreshed on 15 June 2026; these are the new rates.",
                "5x on Lyft rides through 30 September 2027, and 5x on Peloton equipment over $150 through 31 December 2027. Both end, so neither is written in as a rate.",
                "A $50 yearly hotel credit through Chase Travel, and 10% of the year's spend back in points on the account anniversary. Neither changes which card to pay with."
            ]
        )
    }

    // MARK: - Discover

    public static var discoverIt: Card { discoverItEntry.card }

    static var discoverItEntry: CatalogEntry {
        CatalogEntry(
            productID: "discover-it-cash-back",
            card: Card(
                issuer: "Discover",
                name: "it Cash Back",
                currency: .cashBack,
                rules: [
                    CategoryRule(category: .base, rate: 1)
                ],
                rotatingProgram: RotatingProgram(
                    rate: 5,
                    cap: EarnCap(limitDollars: 1_500, period: .quarterly),
                    quarters: [
                        RotatingQuarter(
                            quarter: Quarter(year: 2026, index: 3),
                            categories: [.gas, .drugstores, .transit],
                            summary: "Gas stations, drug stores, and transportation",
                            activationDeadline: date(2026, 9, 30)
                        ),
                        RotatingQuarter(
                            quarter: Quarter(year: 2026, index: 4),
                            categories: [.dining, .entertainment],
                            summary: "Restaurants, entertainment, and utilities",
                            activationDeadline: date(2026, 12, 31)
                        )
                    ],
                    // Discover publishes the whole year ahead, which is why two
                    // quarters are known here and only one is known for Chase.
                    knownThrough: Quarter(year: 2026, index: 4),
                    sourceURL: "https://www.discover.com/credit-cards/cash-back/cashback-calendar.html"
                ),
                perks: [.firstYearCashbackMatch],
                foreignTransactionFeePercent: 0,
                annualFeeDollars: 0,
                artKey: "graphite",
                finish: .matte
            ),
            network: .discover,
            aliases: ["Discover it", "Discover it Cash Back", "Discover cashback"],
            termsURL: "https://www.discover.com/credit-cards/cash-back/it-card.html",
            checkedOn: checkedOn,
            notModelled: [
                "Utilities are part of Q4's 5%, but a utility bill is not a shop and nothing here can notice one."
            ]
        )
    }

    // MARK: - American Express

    public static var amexBlueCashPreferred: Card { amexBlueCashPreferredEntry.card }

    static var amexBlueCashPreferredEntry: CatalogEntry {
        CatalogEntry(
            productID: "amex-blue-cash-preferred",
            card: Card(
                issuer: "Amex",
                name: "Blue Cash Preferred",
                currency: .cashBack,
                rules: [
                    CategoryRule(
                        category: .groceries,
                        rate: 6,
                        cap: EarnCap(limitDollars: 6_000, period: .annual),
                        note: "U.S. supermarkets only."
                    ),
                    CategoryRule(category: .streaming, rate: 6, note: "Select U.S. streaming subscriptions."),
                    CategoryRule(category: .transit, rate: 3, note: "Includes taxis, rideshare, parking, tolls, trains and buses."),
                    CategoryRule(category: .rideshare, rate: 3),
                    CategoryRule(category: .gas, rate: 3, note: "U.S. gas stations only."),
                    CategoryRule(category: .base, rate: 1)
                ],
                notes: [
                    CategoryNote(
                        category: .warehouseClub,
                        text: "Warehouse clubs do not code as supermarkets. This card earns its base rate at Costco and Sam's Club."
                    ),
                    CategoryNote(
                        category: .departmentStore,
                        text: "Walmart and Target do not code as supermarkets either, however much food they sell."
                    ),
                    CategoryNote(
                        category: .gas,
                        text: "A gas station with a large convenience store may code as general retail instead of gas."
                    )
                ],
                foreignTransactionFeePercent: 2.7,
                annualFeeDollars: 95,
                artKey: "azure",
                finish: .matte
            ),
            network: .amex,
            issuerFullName: "American Express",
            aliases: ["American Express Blue Cash Preferred", "Blue Cash Preferred", "Blue Cash", "BCP"],
            termsURL: "https://www.americanexpress.com/us/credit-cards/card/blue-cash-preferred/",
            checkedOn: checkedOn,
            notModelled: [
                "New accounts pay no annual fee for the first year. The $95 here is what it settles at."
            ]
        )
    }

    public static var amexGold: Card { amexGoldEntry.card }

    static var amexGoldEntry: CatalogEntry {
        CatalogEntry(
            productID: "amex-gold",
            card: Card(
                issuer: "Amex",
                name: "Gold",
                currency: .membershipRewards,
                rules: [
                    CategoryRule(
                        category: .dining,
                        rate: 4,
                        // Added from 2025. Most people never reach it, but a
                        // cap that exists and is not modelled is a card that
                        // keeps being recommended after it stopped paying.
                        cap: EarnCap(limitDollars: 50_000, period: .annual),
                        note: "Restaurants worldwide."
                    ),
                    CategoryRule(
                        category: .groceries,
                        rate: 4,
                        cap: EarnCap(limitDollars: 25_000, period: .annual),
                        note: "U.S. supermarkets only."
                    ),
                    CategoryRule(category: .travelPortal, rate: 5, note: "Prepaid hotels through Amex Travel."),
                    CategoryRule(category: .flights, rate: 3, note: "Booked with the airline or through Amex Travel."),
                    CategoryRule(category: .base, rate: 1)
                ],
                perks: [.noForeignTransactionFee, .annualTravelCredit, .purchaseProtection],
                notes: [
                    CategoryNote(
                        category: .warehouseClub,
                        text: "Warehouse clubs do not code as supermarkets."
                    ),
                    CategoryNote(
                        category: .travelPortal,
                        text: "The 5x is for prepaid hotels. Car rentals and cruises booked the same way earn 2x."
                    )
                ],
                foreignTransactionFeePercent: 0,
                annualFeeDollars: 325,
                artKey: "gold",
                finish: .metal
            ),
            network: .amex,
            issuerFullName: "American Express",
            aliases: ["American Express Gold Card", "Amex Gold", "Gold Card"],
            termsURL: "https://www.americanexpress.com/us/credit-cards/card/gold-card/",
            checkedOn: checkedOn,
            notModelled: [
                "Up to $424 a year in credits tied to named merchants. They are worth money but they do not change which card to hand over."
            ]
        )
    }

    // MARK: - Citi

    public static var citiDoubleCash: Card { citiDoubleCashEntry.card }

    static var citiDoubleCashEntry: CatalogEntry {
        CatalogEntry(
            productID: "citi-double-cash",
            card: Card(
                issuer: "Citi",
                name: "Double Cash",
                currency: .cashBack,
                rules: [
                    CategoryRule(category: .base, rate: 2, note: "1% when you buy, 1% when you pay it off.")
                ],
                foreignTransactionFeePercent: 3,
                annualFeeDollars: 0,
                artKey: "slate",
                finish: .matte
            ),
            network: .mastercard,
            aliases: ["Citi Double Cash", "Double Cash"],
            termsURL: "https://www.citi.com/credit-cards/citi-double-cash-credit-card",
            checkedOn: checkedOn,
            notModelled: [
                "Hotels, car rentals and attractions booked through Citi Travel have been earning 5%, but Citi has run that as a dated offer before now and the current end date could not be confirmed. Left out rather than promised.",
                "Rewards arrive as ThankYou Points. One cent each as cash back, possibly more if transferred to an airline."
            ]
        )
    }

    public static var costcoAnywhereVisa: Card { costcoAnywhereVisaEntry.card }

    static var costcoAnywhereVisaEntry: CatalogEntry {
        CatalogEntry(
            productID: "citi-costco-anywhere-visa",
            card: Card(
                issuer: "Citi",
                name: "Costco Anywhere Visa",
                currency: .cashBack,
                rules: [
                    CategoryRule(
                        category: .gas,
                        rate: 4,
                        cap: EarnCap(limitDollars: 7_000, period: .annual),
                        note: "Gas and EV charging. The cap is shared with gas bought at Costco."
                    ),
                    CategoryRule(category: .dining, rate: 3),
                    CategoryRule(category: .travel, rate: 3),
                    CategoryRule(category: .flights, rate: 3),
                    CategoryRule(category: .hotels, rate: 3),
                    CategoryRule(category: .warehouseClub, rate: 2, note: "Costco and Costco.com."),
                    CategoryRule(category: .base, rate: 1)
                ],
                perks: [.noForeignTransactionFee],
                notes: [
                    CategoryNote(
                        category: .warehouseClub,
                        text: "Rewards arrive once a year as a certificate, not as a statement credit."
                    ),
                    CategoryNote(
                        category: .gas,
                        text: "Gas bought at a Costco station earns 5%, not the 4% shown here."
                    )
                ],
                foreignTransactionFeePercent: 0,
                annualFeeDollars: 0,
                artKey: "forest",
                finish: .glossy
            ),
            network: .visa,
            aliases: ["Costco Anywhere Visa", "Costco Visa", "Costco card", "Costco"],
            termsURL: "https://www.citi.com/credit-cards/costco-anywhere-visa-card",
            checkedOn: checkedOn,
            notModelled: [
                "No annual fee, but it needs an active Costco membership, which costs money this app does not count."
            ]
        )
    }

    // MARK: - Capital One

    public static var capitalOneSavor: Card { capitalOneSavorEntry.card }

    static var capitalOneSavorEntry: CatalogEntry {
        CatalogEntry(
            productID: "capital-one-savor",
            card: Card(
                issuer: "Capital One",
                name: "Savor",
                currency: .cashBack,
                rules: [
                    CategoryRule(category: .travelPortal, rate: 5, note: "Hotels, vacation rentals, cars and activities through Capital One Travel."),
                    CategoryRule(category: .dining, rate: 3),
                    CategoryRule(category: .entertainment, rate: 3),
                    CategoryRule(category: .streaming, rate: 3, note: "Popular streaming services."),
                    CategoryRule(category: .groceries, rate: 3),
                    CategoryRule(category: .base, rate: 1)
                ],
                perks: [.noForeignTransactionFee],
                notes: [
                    CategoryNote(
                        category: .warehouseClub,
                        text: "Superstores and warehouse clubs are excluded from the grocery bonus."
                    ),
                    CategoryNote(
                        category: .departmentStore,
                        text: "Walmart and Target count as superstores, so groceries bought there earn the base rate."
                    )
                ],
                foreignTransactionFeePercent: 0,
                annualFeeDollars: 0,
                artKey: "ember",
                finish: .glossy
            ),
            network: .mastercard,
            aliases: ["Capital One Savor", "Savor", "Savor Rewards"],
            termsURL: "https://www.capitalone.com/credit-cards/savor-dining-rewards/",
            checkedOn: checkedOn,
            notModelled: [
                "8% back on Capital One Entertainment bookings. That is a website, not a place you walk into, so it never comes up here."
            ]
        )
    }

    // MARK: - Wells Fargo

    public static var wellsFargoActiveCash: Card { wellsFargoActiveCashEntry.card }

    static var wellsFargoActiveCashEntry: CatalogEntry {
        CatalogEntry(
            productID: "wells-fargo-active-cash",
            card: Card(
                issuer: "Wells Fargo",
                name: "Active Cash",
                currency: .cashBack,
                rules: [
                    CategoryRule(category: .base, rate: 2)
                ],
                perks: [.cellPhoneProtection],
                foreignTransactionFeePercent: 3,
                annualFeeDollars: 0,
                artKey: "crimson",
                finish: .matte
            ),
            network: .visa,
            aliases: ["Wells Fargo Active Cash", "Active Cash"],
            termsURL: "https://www.wellsfargo.com/credit-cards/active-cash/",
            checkedOn: checkedOn,
            notModelled: [
                "Cell phone cover up to $600 against theft or damage, with a $25 excess, when the bill is paid with this card."
            ]
        )
    }

    // MARK: - Dates

    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar.date(from: components) ?? Date()
    }
}
