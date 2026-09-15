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

        // The shop is the title and the card is the body. Both fit; neither
        // is repeated. See `headline(for:in:)` for why that way round.
        XCTAssertTrue(reminder.title.contains("Corner Bistro"), reminder.title)
        XCTAssertTrue(reminder.body.contains("Amex Gold"), reminder.body)
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
        XCTAssertFalse(reminder.title.contains("Corner Bistro"), reminder.title)
        XCTAssertFalse(reminder.body.contains("Corner Bistro"), reminder.body)
        // The kind of place, not the spending bucket: nobody is standing
        // outside a "Dining".
        XCTAssertTrue(reminder.title.contains("Restaurant nearby"), reminder.title)
    }

    // MARK: - Short enough to read at a glance

    /// The failure this replaced: "Transit nearby. Use Capital One S…" — the
    /// title spent its whole budget on the place *and* the card, so iOS cut
    /// off the card, which is the one thing the reminder exists to say.
    func testTheTitleIsShortEnoughNotToBeTruncated() throws {
        let reminder = try XCTUnwrap(engine.reminder(
            for: arrival(at: bistro, confidence: .categoryOnly),
            cards: [CardCatalog.amexGold],
            asOf: Fixture.inQ3
        ))
        XCTAssertLessThanOrEqual(reminder.title.count, 40, reminder.title)
    }

    /// A category's emoji leads the title, so the kind of place registers
    /// before a word of it is read.
    func testTheTitleLeadsWithTheCategoryEmoji() throws {
        let reminder = try XCTUnwrap(engine.reminder(
            for: arrival(at: market),
            cards: [CardCatalog.amexBlueCashPreferred, CardCatalog.citiDoubleCash],
            asOf: Fixture.inQ3
        ))
        XCTAssertTrue(reminder.title.hasPrefix(SpendingCategory.groceries.emoji), reminder.title)
    }

    /// One instruction, in the shape somebody would say it out loud.
    func testTheBodyIsOneInstruction() throws {
        let reminder = try XCTUnwrap(engine.reminder(
            for: arrival(at: bistro),
            cards: [CardCatalog.amexGold],
            asOf: Fixture.inQ3
        ))
        XCTAssertEqual(reminder.body, "Use Amex Gold for 4x at restaurants.")
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

    // MARK: - Why it stayed quiet

    /// Silence is half the product, so the reason for it has to survive. A
    /// `nil` that loses why nothing was said leaves nobody able to tell
    /// restraint from a bug.

    func testAnEmptyWalletSaysWhyItSaidNothing() {
        let decision = engine.decide(for: arrival(at: bistro), cards: [], asOf: Fixture.inQ3)
        XCTAssertEqual(decision, .stayQuiet(.noCards))
    }

    func testAFlatWalletSaysWhyItSaidNothing() {
        let flatWallet = [CardCatalog.citiDoubleCash, CardCatalog.wellsFargoActiveCash]
        let decision = engine.decide(for: arrival(at: bistro), cards: flatWallet, asOf: Fixture.inQ3)
        XCTAssertEqual(decision, .stayQuiet(.noMeaningfulEdge))
    }

    func testATrivialEdgeSaysWhyItSaidNothing() {
        let wallet = [flatCard("Just Ahead", rate: 2.2), flatCard("Runner Up", rate: 2.0)]
        let decision = engine.decide(for: arrival(at: bistro), cards: wallet, asOf: Fixture.inQ3)
        XCTAssertEqual(decision, .stayQuiet(.noMeaningfulEdge))
    }

    /// A reminder that goes out carries the numbers behind it, frozen, so the
    /// suggestion can be priced hours later against the wallet as it was.
    func testAReminderCarriesTheNumbersBehindIt() throws {
        let wallet = [CardCatalog.citiDoubleCash, CardCatalog.amexGold]
        let decision = engine.decide(for: arrival(at: bistro), cards: wallet, asOf: Fixture.inQ3)
        let snapshot = try XCTUnwrap(decision.snapshot)

        XCTAssertEqual(snapshot.cardName, "Amex Gold")
        XCTAssertEqual(snapshot.cardProductID, "amex-gold")
        XCTAssertEqual(snapshot.centsPerDollar, 4, accuracy: 0.0001)
        XCTAssertEqual(snapshot.alternateCardName, "Citi Double Cash")
        XCTAssertEqual(snapshot.alternateCentsPerDollar ?? 0, 2, accuracy: 0.0001)
        XCTAssertEqual(snapshot.category, .dining)
        XCTAssertEqual(decision.reminder?.cardID, snapshot.cardID)
    }

    /// The snapshot holds no merchant, even though the sentence on the lock
    /// screen names one. Which shop is what the words need; it is not what the
    /// arithmetic needs, and keeping it would turn a ledger of estimates into
    /// a record of where somebody has been.
    func testTheFrozenNumbersHoldNoMerchant() throws {
        let decision = engine.decide(
            for: arrival(at: bistro),
            cards: [CardCatalog.amexGold, CardCatalog.citiDoubleCash],
            asOf: Fixture.inQ3
        )
        let snapshot = try XCTUnwrap(decision.snapshot)
        XCTAssertTrue(decision.reminder?.title.contains("Corner Bistro") ?? false)
        XCTAssertFalse(snapshot.followUpDescription.contains("Corner Bistro"))

        let json = try XCTUnwrap(String(data: JSONEncoder().encode(snapshot), encoding: .utf8))
        XCTAssertFalse(json.contains("Corner Bistro"), json)
    }

    // MARK: - A win too small to interrupt anyone for

    /// A card with a real dining-specific rate, not just a base rate — the
    /// edge check only ever runs once something has already earned a bonus,
    /// and a `.base`-only rule never does.
    private func flatCard(_ name: String, rate: Double) -> Card {
        Card(issuer: "Test", name: name, rules: [
            CategoryRule(category: .dining, rate: rate),
            CategoryRule(category: .base, rate: 1)
        ])
    }

    /// 2.0% versus 2.2% is a real edge and a genuinely trivial one — two cents
    /// on a ten-dollar lunch. Not worth a lock-screen notification.
    func testATrivialEdgeStaysQuiet() {
        let wallet = [flatCard("Just Ahead", rate: 2.2), flatCard("Runner Up", rate: 2.0)]
        XCTAssertNil(engine.reminder(for: arrival(at: bistro), cards: wallet, asOf: Fixture.inQ3))
    }

    /// 3% versus 2% is a full cent per dollar and stays worth saying.
    func testARealEdgeStillNotifies() throws {
        let wallet = [flatCard("Clear Winner", rate: 3), flatCard("Runner Up", rate: 2)]
        let reminder = try XCTUnwrap(engine.reminder(for: arrival(at: bistro), cards: wallet, asOf: Fixture.inQ3))
        XCTAssertTrue(reminder.body.contains("Clear Winner"), reminder.body)
    }

    /// One card in the wallet has nothing to be trivial *next to*. The edge
    /// check must not silence the only card there is.
    func testASingleCardHasNoRunnerUpToBeTrivialAgainst() throws {
        let reminder = try XCTUnwrap(engine.reminder(
            for: arrival(at: bistro),
            cards: [flatCard("Only Card", rate: 2.1)],
            asOf: Fixture.inQ3
        ))
        XCTAssertTrue(reminder.body.contains("Only Card"), reminder.body)
    }

    /// An activation nudge survives a trivial edge: it is advice to switch a
    /// bonus on, not a claim that the currently-winning card pulls meaningfully
    /// ahead of the runner-up sitting right next to it.
    func testATrivialEdgeStillCarriesAnActivationNudge() throws {
        var rotator = rotatingCard(activated: false)
        rotator.rules = [CategoryRule(category: .base, rate: 2.0)]
        let wallet = [rotator, flatCard("Runner Up", rate: 1.9)]
        let reminder = try XCTUnwrap(engine.reminder(for: arrival(at: bistro), cards: wallet, asOf: Fixture.inQ3))
        XCTAssertTrue(reminder.body.contains("Activate"), reminder.body)
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
        XCTAssertTrue(reminder.body.contains("Rotator"), reminder.body)
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
