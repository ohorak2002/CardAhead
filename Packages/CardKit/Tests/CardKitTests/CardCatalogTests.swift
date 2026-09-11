import XCTest
@testable import CardKit

/// The audit, written down so it cannot quietly stop being true.
///
/// Card terms are facts about somebody else's product. They change without
/// telling us, and the only defence is to record where each number came from
/// and refuse to ship one that has no source.
final class CardCatalogTests: XCTestCase {

    /// A fixed "today" so these tests do not start failing on a calendar
    /// boundary. Chosen as the day the catalog was audited.
    private let auditDay = CardCatalog.checkedOn

    // MARK: - Provenance

    func testEveryEntryCitesTheIssuersOwnPage() throws {
        let issuerHosts = [
            "chase.com", "americanexpress.com", "discover.com",
            "citi.com", "capitalone.com", "wellsfargo.com"
        ]
        for entry in CardCatalog.entries {
            let url = try XCTUnwrap(URL(string: entry.termsURL), entry.id)
            XCTAssertEqual(url.scheme, "https", entry.id)
            let host = try XCTUnwrap(url.host, entry.id)
            XCTAssertTrue(
                issuerHosts.contains { host == $0 || host.hasSuffix(".\($0)") },
                "\(entry.id) cites \(host), which is not the issuer. Review sites are downstream of the same drift this field exists to catch."
            )
        }
    }

    func testTheWholeCatalogWasCheckedOnOneDay() {
        for entry in CardCatalog.entries {
            XCTAssertEqual(entry.checkedOn, CardCatalog.checkedOn, entry.id)
        }
    }

    func testNumbersGoStaleAndSaySo() {
        let entry = CardCatalog.chaseFreedomFlexEntry
        XCTAssertFalse(entry.isStale(asOf: auditDay.addingTimeInterval(60 * 60 * 24 * 30)))
        XCTAssertTrue(entry.isStale(asOf: auditDay.addingTimeInterval(60 * 60 * 24 * 365)))
    }

    // MARK: - Which product is it

    /// The id is what a saved card points back at, so it has to outlive the
    /// display name. Issuers rename cards.
    func testEveryProductIDIsUniqueAndStablyShaped() {
        var seen: Set<String> = []
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        for entry in CardCatalog.entries {
            XCTAssertTrue(seen.insert(entry.productID).inserted, "\(entry.productID) is used twice")
            XCTAssertFalse(entry.productID.isEmpty)
            XCTAssertTrue(
                entry.productID.unicodeScalars.allSatisfy(allowed.contains),
                "\(entry.productID) should be lower case and hyphenated"
            )
        }
    }

    func testEveryCatalogCardKnowsWhichProductItIs() {
        for entry in CardCatalog.entries {
            XCTAssertEqual(entry.card.catalogProductID, entry.productID, entry.id)
            XCTAssertTrue(entry.card.isCatalogCard, entry.id)
            XCTAssertEqual(CardCatalog.entry(for: entry.card)?.productID, entry.productID)
        }
    }

    func testACardTypedInByHandBelongsToNoProduct() {
        let byHand = Card(issuer: "Local credit union", name: "Everyday")
        XCTAssertFalse(byHand.isCatalogCard)
        XCTAssertNil(CardCatalog.entry(for: byHand))
    }

    /// Searching the display name alone found none of these, which is most of
    /// what anybody actually types.
    func testNicknamesAndFullNamesFindTheCard() throws {
        let expected: [(query: String, productID: String)] = [
            ("amex gold", "amex-gold"),
            ("American Express Gold Card", "amex-gold"),
            ("gold card", "amex-gold"),
            ("CSP", "chase-sapphire-preferred"),
            ("BCP", "amex-blue-cash-preferred"),
            ("costco visa", "citi-costco-anywhere-visa"),
            ("double cash", "citi-double-cash"),
            ("active cash", "wells-fargo-active-cash")
        ]
        for expectation in expected {
            let found = CardCatalog.searchEntries(expectation.query)
            XCTAssertTrue(
                found.contains { $0.productID == expectation.productID },
                "\"\(expectation.query)\" did not find \(expectation.productID)"
            )
        }
    }

    /// Every word has to land, or "chase gold" would hand somebody an Amex.
    func testSearchNeedsEveryWordToMatch() {
        XCTAssertTrue(CardCatalog.searchEntries("chase gold").isEmpty)
        XCTAssertEqual(CardCatalog.searchEntries("chase sapphire").count, 1)
    }

    func testTheNetworkIsSearchableSoVisaFindsVisaCards() {
        let visa = CardCatalog.searchEntries("visa").map(\.productID)
        XCTAssertTrue(visa.contains("chase-sapphire-preferred"))
        XCTAssertFalse(visa.contains("amex-gold"))
    }

    func testIssuersRollUpTheCatalog() throws {
        let issuers = CardCatalog.issuers
        XCTAssertEqual(issuers.map(\.name).sorted(), ["Amex", "Capital One", "Chase", "Citi", "Discover", "Wells Fargo"])

        let amex = try XCTUnwrap(issuers.first { $0.name == "Amex" })
        // "Amex" is what fits on a card. "American Express" is what somebody types.
        XCTAssertEqual(amex.fullName, "American Express")
        XCTAssertEqual(amex.cardCount, 2)
        XCTAssertEqual(issuers.first { $0.name == "Citi" }?.cardCount, 2)
        XCTAssertEqual(CardCatalog.entries(issuedBy: "Chase").count, 2)
    }

    /// The rule this whole change exists for: "Gold" does not identify a card.
    func testTwoProductsCalledGoldStayTellableApart() {
        let personal = CardCatalog.amexGoldEntry
        let business = CatalogEntry(
            productID: "amex-business-gold",
            card: Card(issuer: "Amex", name: "Business Gold"),
            network: .amex,
            variant: .business,
            issuerFullName: "American Express",
            aliases: ["American Express Business Gold"],
            termsURL: "https://www.americanexpress.com/us/credit-cards/card/business-gold/",
            checkedOn: CardCatalog.checkedOn
        )

        XCTAssertNotEqual(personal.productID, business.productID)
        XCTAssertTrue(business.matches("business gold"))
        XCTAssertFalse(personal.matches("business gold"))
        XCTAssertTrue(personal.matches("gold"))
        XCTAssertTrue(business.matches("gold"))
    }

    // MARK: - Rotating categories

    /// The anti-invention rule. A quarter that ships without the issuer's own
    /// wording beside it is a quarter somebody made up, which is exactly what
    /// used to be in here.
    func testNoQuarterShipsWithoutTheIssuersOwnWording() {
        for entry in CardCatalog.entries {
            for quarter in entry.card.rotatingProgram?.quarters ?? [] {
                let summary = quarter.summary ?? ""
                XCTAssertFalse(
                    summary.isEmpty,
                    "\(entry.id) \(quarter.quarter) has categories but no record of what the issuer actually announced"
                )
                XCTAssertFalse(quarter.enteredByUser, "\(entry.id) ships a quarter marked as user-entered")
            }
        }
    }

    func testNoQuarterShipsBeyondWhatAnybodyHasPublished() throws {
        for entry in CardCatalog.entries {
            guard let program = entry.card.rotatingProgram else { continue }
            let edge = try XCTUnwrap(program.knownThrough, "\(entry.id) has a rotating programme with no forward edge")
            for quarter in program.quarters {
                XCTAssertLessThanOrEqual(quarter.quarter, edge, entry.id)
            }
        }
    }

    func testEveryRotatingProgrammeSaysWhereToLookThisQuarterUp() {
        for entry in CardCatalog.entries {
            guard let program = entry.card.rotatingProgram else { continue }
            XCTAssertNotNil(program.sourceURL, "\(entry.id) gives the user nowhere to check")
        }
    }

    /// Chase announces about a fortnight ahead; Discover publishes the year. So
    /// on the audit day one of them knows Q4 and the other does not, and the
    /// app has to be able to tell the difference.
    func testChaseHasNotPublishedQ4AndDiscoverHas() throws {
        let q4 = Quarter(year: 2026, index: 4)
        let chase = try XCTUnwrap(CardCatalog.chaseFreedomFlex.rotatingProgram)
        let discover = try XCTUnwrap(CardCatalog.discoverIt.rotatingProgram)

        XCTAssertEqual(chase.status(for: q4), .unannounced)
        XCTAssertTrue(chase.needsCategories(asOf: CardCatalog.date(2026, 11, 1)))

        guard case .bonus(let known) = discover.status(for: q4) else {
            return XCTFail("Discover's Q4 should be known")
        }
        XCTAssertEqual(known.categories, [.dining, .entertainment])
        XCTAssertFalse(discover.needsCategories(asOf: CardCatalog.date(2026, 11, 1)))
    }

    func testThisQuarterIsKnownForBoth() throws {
        let q3 = Quarter(year: 2026, index: 3)
        let chase = try XCTUnwrap(CardCatalog.chaseFreedomFlex.rotatingProgram)

        guard case .bonus(let quarter) = chase.status(for: q3) else {
            return XCTFail("Q3 should be known")
        }
        XCTAssertEqual(quarter.categories, [.gas, .transit, .entertainment])
        XCTAssertFalse(chase.needsCategories(asOf: Fixture.inQ3))
        // Chase closes activation before the quarter ends. Missing it costs the
        // whole bonus, so the date has to be the real one.
        XCTAssertEqual(quarter.activationDeadline, CardCatalog.date(2026, 9, 14))
    }

    /// A quarter the app never kept is not a quarter with no bonus.
    func testAQuarterWeSimplyDoNotHaveIsNotReportedAsNoBonus() throws {
        let chase = try XCTUnwrap(CardCatalog.chaseFreedomFlex.rotatingProgram)
        XCTAssertEqual(chase.status(for: Quarter(year: 2026, index: 1)), .unannounced)
    }

    func testEnteringAQuarterMovesTheForwardEdge() {
        var program = RotatingProgram(rate: 5, knownThrough: Quarter(year: 2026, index: 3))
        program.setQuarter(RotatingQuarter(
            quarter: Quarter(year: 2026, index: 4),
            categories: [.dining],
            summary: "Restaurants",
            enteredByUser: true
        ))
        XCTAssertEqual(program.knownThrough, Quarter(year: 2026, index: 4))
        XCTAssertFalse(program.needsCategories(asOf: CardCatalog.date(2026, 11, 1)))
    }

    func testEnteringAQuarterTwiceReplacesItRatherThanDuplicating() {
        var program = RotatingProgram(rate: 5)
        let q4 = Quarter(year: 2026, index: 4)
        program.setQuarter(RotatingQuarter(quarter: q4, categories: [.dining], summary: "Restaurants"))
        program.setQuarter(RotatingQuarter(quarter: q4, categories: [.gas], summary: "Petrol"))

        XCTAssertEqual(program.quarters.count, 1)
        XCTAssertEqual(program.quarter(q4)?.categories, [.gas])
    }

    // MARK: - The numbers themselves

    func testAnnualFeesMatchIssuerTerms() {
        let expected: [String: Money] = [
            "Chase Freedom Flex": 0,
            "Chase Sapphire Preferred": 95,
            "Discover it Cash Back": 0,
            "Amex Blue Cash Preferred": 95,
            "Amex Gold": 325,
            "Citi Double Cash": 0,
            "Citi Costco Anywhere Visa": 0,
            "Capital One Savor": 0,
            "Wells Fargo Active Cash": 0
        ]
        for card in CardCatalog.all {
            XCTAssertEqual(card.annualFeeDollars, expected[card.displayName], card.displayName)
        }
    }

    func testForeignTransactionFeesMatchIssuerTerms() {
        let expected: [String: Double] = [
            "Chase Freedom Flex": 3,
            "Chase Sapphire Preferred": 0,
            "Discover it Cash Back": 0,
            "Amex Blue Cash Preferred": 2.7,
            "Amex Gold": 0,
            "Citi Double Cash": 3,
            "Citi Costco Anywhere Visa": 0,
            "Capital One Savor": 0,
            "Wells Fargo Active Cash": 3
        ]
        for card in CardCatalog.all {
            XCTAssertEqual(card.foreignTransactionFeePercent, expected[card.displayName], card.displayName)
        }
    }

    func testCapsMatchIssuerTerms() {
        let expected: [(card: Card, category: SpendingCategory, limit: Money, period: CapPeriod)] = [
            (CardCatalog.amexBlueCashPreferred, .groceries, 6_000, .annual),
            (CardCatalog.amexGold, .groceries, 25_000, .annual),
            // Added from 2025 and missing here until this audit. A cap that
            // exists and is not modelled is a card that keeps being
            // recommended after it stopped paying the rate it promised.
            (CardCatalog.amexGold, .dining, 50_000, .annual),
            (CardCatalog.costcoAnywhereVisa, .gas, 7_000, .annual)
        ]
        for expectation in expected {
            let cap = expectation.card.rule(for: expectation.category)?.cap
            XCTAssertEqual(cap?.limitDollars, expectation.limit, "\(expectation.card.displayName) \(expectation.category)")
            XCTAssertEqual(cap?.period, expectation.period, "\(expectation.card.displayName) \(expectation.category)")
        }
    }

    func testRotatingCapsAreFifteenHundredAQuarter() {
        for card in [CardCatalog.chaseFreedomFlex, CardCatalog.discoverIt] {
            let cap = card.rotatingProgram?.cap
            XCTAssertEqual(cap?.limitDollars, 1_500, card.displayName)
            XCTAssertEqual(cap?.period, .quarterly, card.displayName)
        }
    }

    /// The one that mattered most to this app. Sapphire Preferred's 3x grocery
    /// bonus is for online orders only, and this app's entire job is telling
    /// you what to pay with while standing in a shop. Written as a grocery rule
    /// it would have been confidently wrong at exactly the moment it spoke.
    func testSapphirePreferredClaimsNoInStoreGroceryBonus() {
        let card = CardCatalog.chaseSapphirePreferred
        XCTAssertNil(card.rule(for: .groceries))
        XCTAssertTrue(
            card.notes(for: .groceries).contains { $0.text.contains("online") },
            "the reason has to travel with the card, or somebody re-adds the rule"
        )
    }

    func testSapphirePreferredHasTheRatesItGainedInJune() {
        let card = CardCatalog.chaseSapphirePreferred
        XCTAssertEqual(card.rule(for: .gas)?.rate, 3)
        XCTAssertEqual(card.rule(for: .travelPortal)?.rate, 5)
        XCTAssertEqual(card.rule(for: .dining)?.rate, 3)
        XCTAssertEqual(card.rule(for: .travel)?.rate, 2)
    }

    /// Amex Gold's 5x is prepaid hotels through Amex Travel, not hotels in
    /// general, and the app must not tell somebody to use it at a front desk.
    func testAmexGoldPutsItsFiveTimesRateOnThePortalNotOnHotels() {
        let card = CardCatalog.amexGold
        XCTAssertEqual(card.rule(for: .travelPortal)?.rate, 5)
        XCTAssertNil(card.rule(for: .hotels))
    }
}
