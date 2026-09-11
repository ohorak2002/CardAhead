import XCTest
@testable import CardKit

/// What a person reads at a till, and when they should be left alone.
final class ArrivalReminderTests: XCTestCase {

    let engine = RecommendationEngine()

    private func arrival(
        at merchant: Merchant,
        confidence: MerchantConfidence = .exact
    ) -> PendingArrival {
        var place = merchant
        place.confidence = confidence
        return PendingArrival(
            regionID: RegionPlanner.regionID(for: place),
            merchant: place,
            enteredAt: Fixture.inQ3,
            confirmAt: Fixture.inQ3.addingTimeInterval(240)
        )
    }

    private var bistro: Merchant {
        Fixture.merchant("bistro", category: .dining, metersNorth: 20, name: "Corner Bistro")
    }

    private var market: Merchant {
        Fixture.merchant("market", category: .groceries, metersNorth: 20, name: "Hill Market")
    }

    // MARK: - Saying something

    func testTheReminderNamesTheWinningCardAndTheShop() throws {
        let wallet = [CardCatalog.citiDoubleCash, CardCatalog.amexGold]
        let reminder = try XCTUnwrap(engine.reminder(
            for: arrival(at: bistro),
            cards: wallet,
            asOf: Fixture.inQ3
        ))

        XCTAssertTrue(reminder.title.contains("Amex Gold"), reminder.title)
        XCTAssertTrue(reminder.body.contains("Corner Bistro"), reminder.body)
        XCTAssertEqual(reminder.cardID, wallet[1].id)
        XCTAssertEqual(reminder.merchantName, "Corner Bistro")
        XCTAssertEqual(reminder.category, .dining)
    }

    /// The tap has to land on the card the sentence just named.
    func testTheCardToOpenIsTheCardNamed() throws {
        let wallet = [CardCatalog.amexGold, CardCatalog.citiDoubleCash]
        let reminder = try XCTUnwrap(engine.reminder(
            for: arrival(at: bistro),
            cards: wallet,
            asOf: Fixture.inQ3
        ))
        XCTAssertEqual(reminder.cardName, "Amex Gold")
        XCTAssertEqual(reminder.cardID, wallet[0].id)
    }

    /// A mall or a food court cannot be pinned to one business, so the reminder
    /// talks about the category instead of naming the wrong restaurant.
    func testAnUnresolvedPlaceIsNotGivenAName() throws {
        let reminder = try XCTUnwrap(engine.reminder(
            for: arrival(at: bistro, confidence: .categoryOnly),
            cards: [CardCatalog.amexGold],
            asOf: Fixture.inQ3
        ))
        XCTAssertNil(reminder.merchantName)
        XCTAssertFalse(reminder.body.contains("Corner Bistro"), reminder.body)
        XCTAssertTrue(reminder.title.contains("Dining"), reminder.title)
    }

    // MARK: - Saying nothing

    func testAnEmptyWalletSaysNothing() {
        XCTAssertNil(engine.reminder(for: arrival(at: bistro), cards: [], asOf: Fixture.inQ3))
    }

    /// Interrupting somebody to tell them every card pays the same is an
    /// interruption with no content in it.
    func testNoBonusHereMeansNoNotification() {
        let flatWallet = [CardCatalog.citiDoubleCash, CardCatalog.wellsFargoActiveCash]
        XCTAssertNil(engine.reminder(for: arrival(at: bistro), cards: flatWallet, asOf: Fixture.inQ3))
    }

    /// The geofence was registered because of the grocery bonus. If the cap is
    /// spent by the time somebody walks in, there is nothing left to say.
    func testASpentCapSilencesTheReminder() {
        let spent = Fixture.exhaustingCap(CardCatalog.amexBlueCashPreferred, category: .groceries)
        XCTAssertNil(engine.reminder(for: arrival(at: market), cards: [spent], asOf: Fixture.inQ3))
    }

    // MARK: - The second sentence

    private func rotatingCard(activated: Bool) -> Card {
        Card(
            issuer: "Test",
            name: "Rotator",
            rules: [CategoryRule(category: .base, rate: 1)],
            rotatingProgram: RotatingProgram(
                rate: 5,
                quarters: [RotatingQuarter(quarter: Fixture.q3, categories: [.dining], isActivated: activated)]
            )
        )
    }

    /// A bonus sitting there unclicked is the one case where the user is about
    /// to lose real money, so it takes the second sentence.
    func testAnUnactivatedBonusIsWorthInterruptingFor() throws {
        let reminder = try XCTUnwrap(engine.reminder(
            for: arrival(at: bistro),
            cards: [rotatingCard(activated: false), CardCatalog.citiDoubleCash],
            asOf: Fixture.inQ3
        ))
        XCTAssertTrue(reminder.body.contains("Activate"), reminder.body)
    }

    func testAnActivatedBonusJustWins() throws {
        let reminder = try XCTUnwrap(engine.reminder(
            for: arrival(at: bistro),
            cards: [rotatingCard(activated: true), CardCatalog.citiDoubleCash],
            asOf: Fixture.inQ3
        ))
        XCTAssertTrue(reminder.title.contains("Rotator"), reminder.title)
        XCTAssertFalse(reminder.body.contains("Activate"), reminder.body)
    }

    /// With nothing about to be lost, the spare sentence goes to the coding
    /// quirk that would otherwise make the reminder wrong.
    func testACaveatTakesTheSecondSentenceWhenNothingIsAtStake() throws {
        let costco = Fixture.merchant(
            "costco",
            category: .warehouseClub,
            metersNorth: 20,
            name: "Costco Wholesale"
        )
        let reminder = try XCTUnwrap(engine.reminder(
            for: arrival(at: costco),
            cards: [CardCatalog.costcoAnywhereVisa, CardCatalog.amexBlueCashPreferred],
            asOf: Fixture.inQ3
        ))
        XCTAssertTrue(reminder.body.contains("certificate"), reminder.body)
    }

    /// One caveat is the ceiling. A lock screen truncates, and the truncated
    /// half is always the part that mattered.
    func testOnlyOneCaveatMakesItOntoTheLockScreen() throws {
        var chatty = CardCatalog.capitalOneSavor
        chatty.notes = [
            CategoryNote(category: .dining, text: "First thing."),
            CategoryNote(category: .dining, text: "Second thing."),
            CategoryNote(category: .dining, text: "Third thing.")
        ]
        let reminder = try XCTUnwrap(engine.reminder(
            for: arrival(at: bistro),
            cards: [chatty],
            asOf: Fixture.inQ3
        ))
        XCTAssertTrue(reminder.body.contains("First thing."), reminder.body)
        XCTAssertFalse(reminder.body.contains("Second thing."), reminder.body)
        XCTAssertFalse(reminder.body.contains("Third thing."), reminder.body)
    }
}
