import XCTest
@testable import CardKit

/// What the app says about a whole wallet rather than about one card — the
/// wallet rows, the Benefits shelves, and the short list of things worth doing.
final class WalletInsightsTests: XCTestCase {

    private let today = Fixture.inQ3

    // MARK: - What each card is for

    /// "Best for dining" has to be true *of this wallet*. A 3x dining card
    /// sitting next to a 4x dining card is not what you should reach for at a
    /// restaurant, and saying so on every scroll is a small lie told often.
    func testACardIsOnlyBestAtWhatItActuallyWins() {
        // Bound once, deliberately: `CardCatalog.amexGold` is a computed
        // property and mints a fresh `id` on every access, so the card asked
        // about has to be the same value that is in the wallet.
        let gold = CardCatalog.amexGold
        let wallet = [gold, CardCatalog.citiDoubleCash]
        // Its best rate is the 5x on hotels prepaid through Amex Travel, not
        // the 4x on dining — which is exactly why the wallet row shows the
        // *group* and says "Best for travel". See `HomeView.bestFor`.
        XCTAssertEqual(WalletInsights.bestCategory(for: gold, in: wallet, asOf: today), .travelPortal)
    }

    /// The label a person reads has to be a phrase a person uses. "Best for
    /// travel booked through the issuer" is accurate and unreadable; the shelf
    /// that category sits on is both.
    func testTheLabelAWalletRowShowsIsTheShelfNotTheRawCategory() throws {
        let gold = CardCatalog.amexGold
        let wallet = [gold, CardCatalog.citiDoubleCash]
        let category = try XCTUnwrap(WalletInsights.bestCategory(for: gold, in: wallet, asOf: today))
        XCTAssertEqual(BenefitGroup.containing(category), .travel)
        XCTAssertEqual(BenefitGroup.containing(category).displayName, "Travel")
    }

    /// A flat card beaten everywhere on bonuses is still the one you reach for
    /// by default, and that is a real thing to say about it.
    func testAFlatCardIsBestForEverythingElse() {
        let citi = CardCatalog.citiDoubleCash
        let wallet = [CardCatalog.amexGold, citi]
        XCTAssertEqual(WalletInsights.bestCategory(for: citi, in: wallet, asOf: today), .base)
    }

    /// A card another card covers completely gets no label rather than a
    /// flattering one.
    func testACardThatWinsNothingSaysNothing() {
        let strictlyWorse = Card(
            issuer: "Zed",
            name: "Basic",
            rules: [CategoryRule(category: .dining, rate: 1), CategoryRule(category: .base, rate: 1)]
        )
        let wallet = [CardCatalog.amexGold, CardCatalog.citiDoubleCash, strictlyWorse]
        XCTAssertNil(WalletInsights.bestCategory(for: strictlyWorse, in: wallet, asOf: today))
    }

    /// The identity rule, written down as a test because CI found it the hard
    /// way: a card that is not *the same value* as the one in the wallet wins
    /// nothing, because winning is decided by `id`. Two accesses of a computed
    /// `CardCatalog` property are two different cards.
    func testACardFromOutsideTheWalletWinsNothing() {
        let wallet = [CardCatalog.amexGold, CardCatalog.citiDoubleCash]
        // Same product, different instance, therefore a different id.
        XCTAssertNil(WalletInsights.bestCategory(for: CardCatalog.amexGold, in: wallet, asOf: today))
    }

    func testTheOnlyCardInAWalletIsBestAtItsOwnBestThing() {
        let gold = CardCatalog.amexGold
        XCTAssertEqual(WalletInsights.bestCategory(for: gold, in: [gold], asOf: today), .travelPortal)

        let savor = CardCatalog.capitalOneSavor
        XCTAssertEqual(WalletInsights.bestCategory(for: savor, in: [savor], asOf: today), .dining)
    }

    // MARK: - The Benefits shelves

    func testBenefitsAreGatheredOntoShelvesInReadingOrder() {
        let groups = WalletInsights.benefitGroups(
            in: [CardCatalog.amexGold, CardCatalog.citiDoubleCash],
            asOf: today
        )
        XCTAssertFalse(groups.isEmpty)
        XCTAssertEqual(groups.map(\.group.sortOrder), groups.map(\.group.sortOrder).sorted())
        XCTAssertTrue(groups.contains { $0.group == .dining })
    }

    /// Two cards paying at a restaurant both belong on the dining shelf, and
    /// the shelf leads with the better of the two.
    func testAShelfKnowsTheBestRateOnIt() throws {
        let groups = WalletInsights.benefitGroups(
            in: [CardCatalog.amexGold, CardCatalog.capitalOneSavor],
            asOf: today
        )
        let dining = try XCTUnwrap(groups.first { $0.group == .dining })
        XCTAssertGreaterThanOrEqual(dining.totalCount, 2)
        XCTAssertEqual(dining.bestRate ?? 0, 4, accuracy: 0.0001)
    }

    /// A cap that is spent is not something you "have" this month.
    func testASpentCapDoesNotCountAsPayingRightNow() throws {
        let spent = Fixture.exhaustingCap(CardCatalog.amexBlueCashPreferred, category: .groceries)
        let groups = WalletInsights.benefitGroups(in: [spent], asOf: today)
        let groceries = try XCTUnwrap(groups.first { $0.group == .groceries })
        XCTAssertEqual(groceries.activeCount, 0)
        XCTAssertGreaterThanOrEqual(groceries.totalCount, 1)
    }

    func testAnEmptyWalletHasNoShelves() {
        XCTAssertTrue(WalletInsights.benefitGroups(in: [], asOf: today).isEmpty)
        XCTAssertEqual(WalletInsights.activeBenefitCount(in: [], asOf: today), 0)
    }

    // MARK: - What runs out soon

    /// Only benefits that carry a real date. An annual travel credit expires
    /// too, and the catalog does not record when — a guessed deadline in a
    /// list headed "running out" is the one somebody rearranges a week around.
    func testOnlyBenefitsWithARealDateCanBeExpiring() {
        // Amex Gold has an annual travel credit and no dated benefit at all.
        XCTAssertTrue(WalletInsights.expiringSoon(in: [CardCatalog.amexGold], asOf: today).isEmpty)
    }

    func testASignupBonusDeadlineInsideTheWindowShowsUp() throws {
        let card = Fixture.withWelcomeBonus(
            CardCatalog.chaseSapphirePreferred,
            rewardUnits: 60_000,
            required: 4_000,
            deadline: today.addingTimeInterval(10 * 24 * 60 * 60)
        )
        let expiring = WalletInsights.expiringSoon(in: [card], asOf: today)
        XCTAssertEqual(expiring.count, 1)
        XCTAssertEqual(try XCTUnwrap(expiring.first).cardName, "Chase Sapphire Preferred")
    }

    func testADeadlineBeyondTheWindowIsNotRunningOut() {
        let card = Fixture.withWelcomeBonus(
            CardCatalog.chaseSapphirePreferred,
            rewardUnits: 60_000,
            required: 4_000,
            deadline: today.addingTimeInterval(120 * 24 * 60 * 60)
        )
        XCTAssertTrue(WalletInsights.expiringSoon(in: [card], asOf: today).isEmpty)
    }

    // MARK: - Worth doing

    /// The one case in this app where doing nothing has a knowable price.
    func testAnUnswitchedQuarterIsAnOpportunity() throws {
        let found = WalletInsights.opportunities(in: [CardCatalog.chaseFreedomFlex], asOf: today)
        let activation = try XCTUnwrap(found.first { $0.kind == .activateRotating })
        XCTAssertTrue(activation.title.lowercased().contains("switch on"), activation.title)
        XCTAssertNotNil(activation.deadline)
    }

    func testAQuarterAlreadySwitchedOnIsNotSomethingToDo() {
        let activated = Fixture.activatingRotation(CardCatalog.chaseFreedomFlex, quarter: Fixture.q3)
        let found = WalletInsights.opportunities(in: [activated], asOf: today)
        XCTAssertFalse(found.contains { $0.kind == .activateRotating })
    }

    func testAnOpenSignupBonusIsSomethingToDo() throws {
        let card = Fixture.withWelcomeBonus(
            CardCatalog.chaseSapphirePreferred,
            rewardUnits: 60_000,
            required: 4_000,
            spent: 1_000,
            deadline: today.addingTimeInterval(20 * 24 * 60 * 60)
        )
        let bonus = try XCTUnwrap(
            WalletInsights.opportunities(in: [card], asOf: today).first { $0.kind == .welcomeBonus }
        )
        XCTAssertTrue(bonus.title.contains("$3,000"), bonus.title)
    }

    /// Most urgent first, or the list is just a pile.
    func testOpportunitiesComeOutSoonestFirst() {
        let soon = Fixture.withWelcomeBonus(
            CardCatalog.chaseSapphirePreferred,
            rewardUnits: 60_000,
            required: 4_000,
            deadline: today.addingTimeInterval(3 * 24 * 60 * 60)
        )
        let later = Fixture.withWelcomeBonus(
            CardCatalog.capitalOneSavor,
            rewardUnits: 20_000,
            required: 500,
            deadline: today.addingTimeInterval(60 * 24 * 60 * 60)
        )
        let found = WalletInsights.opportunities(in: [later, soon], asOf: today)
        let deadlines = found.compactMap(\.deadline)
        XCTAssertEqual(deadlines, deadlines.sorted())
    }

    func testAWalletWithNothingPendingHasNothingToDo() {
        let settled = Fixture.activatingRotation(CardCatalog.chaseFreedomFlex, quarter: Fixture.q3)
        let found = WalletInsights.opportunities(in: [settled, CardCatalog.citiDoubleCash], asOf: today)
        XCTAssertTrue(found.isEmpty, "\(found.map(\.title))")
    }

    // MARK: - The clock on a quarter

    func testAQuarterKnowsWhenItEnds() {
        let q3 = Quarter(year: 2026, index: 3)
        let calendar = Calendar(identifier: .gregorian)
        // Q3 is July through September, so it runs to the first of October.
        let components = calendar.dateComponents([.year, .month, .day], from: q3.end(calendar: calendar))
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 10)
        XCTAssertEqual(components.day, 1)
    }

    func testTheLastQuarterOfTheYearRollsOverCorrectly() {
        let q4 = Quarter(year: 2026, index: 4)
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.year, .month], from: q4.end(calendar: calendar))
        XCTAssertEqual(components.year, 2027)
        XCTAssertEqual(components.month, 1)
    }

    func testDaysRemainingNeverGoesNegative() {
        let longGone = Quarter(year: 2020, index: 1)
        XCTAssertEqual(longGone.daysRemaining(asOf: today), 0)
    }
}
