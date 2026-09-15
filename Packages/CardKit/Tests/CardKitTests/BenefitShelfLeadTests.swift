import XCTest
@testable import CardKit

/// The line every Benefits tile shows under its name.
///
/// **Why this is tested rather than eyeballed.** The rule it replaces —
/// `bestRateText` — is correct and returns nil most of the time, so the
/// screen's whole third line depends on this having something true to say for
/// every shape of wallet. A tile that says "Best with Amex Gold" about a card
/// that does not lead the shelf is exactly the small lie told on every scroll
/// that `bestCategory` already exists to avoid.
///
/// Cards are built here rather than taken from `CardCatalog`, for the reason
/// written on `RunnerUpLineTests`: the thing under test is the choice, not a
/// rate that changes when an issuer re-prices.
final class BenefitShelfLeadTests: XCTestCase {

    private func card(
        _ name: String,
        dining: Double? = nil,
        groceries: Double? = nil,
        style: EarnStyle = .multiplier,
        base: Double = 1
    ) -> Card {
        var rules = [CategoryRule(category: .base, rate: base)]
        if let dining { rules.append(CategoryRule(category: .dining, rate: dining)) }
        if let groceries { rules.append(CategoryRule(category: .groceries, rate: groceries)) }
        return Card(
            issuer: "Test Bank",
            name: name,
            currency: RewardCurrency(name: "Test", centsPerUnit: 1, style: style),
            rules: rules
        )
    }

    private func shelf(_ group: BenefitGroup, in wallet: [Card]) throws -> BenefitGroupSummary {
        let groups = WalletInsights.benefitGroups(in: wallet)
        return try XCTUnwrap(groups.first { $0.group == group })
    }

    // MARK: - Naming the card

    func testOneCardOnTheShelfIsNamed() throws {
        let dining = try shelf(.dining, in: [card("Solo", dining: 4)])
        XCTAssertEqual(dining.lead(), .bestWith("Test Bank Solo"))
    }

    /// The case the old numeric badge could not handle at all: two cards, two
    /// currencies. There is no honest "up to" here, and there *is* an honest
    /// answer to "which one".
    func testTheHigherRateLeadsEvenAcrossCurrencies() throws {
        let wallet = [
            card("Points", dining: 4, style: .multiplier),
            card("Cashback", dining: 3, style: .percent)
        ]
        let dining = try shelf(.dining, in: wallet)
        XCTAssertEqual(dining.lead(), .bestWith("Test Bank Points"))
        XCTAssertNil(
            dining.bestRateText(in: wallet),
            "4x and 3% still must not be compared as a number — that is the whole point"
        )
    }

    /// A tie has no leader, and inventing one would pick a card arbitrarily —
    /// the same card every time, which looks like a considered answer.
    func testATieNamesNobody() throws {
        let wallet = [card("One", dining: 4), card("Two", dining: 4)]
        XCTAssertEqual(try shelf(.dining, in: wallet).lead(), .severalCards(2))
    }

    // MARK: - Attention beats information

    /// Something about to lapse outranks "best with X", because a rewards
    /// organiser whose expiring benefit is one tap deeper is not organising
    /// anything.
    func testEndsSoonWinsOverTheCardName() throws {
        let wallet = [card("Solo", dining: 4)]
        let dining = try shelf(.dining, in: wallet)
        let anyID = try XCTUnwrap(dining.benefits.first?.id)

        XCTAssertEqual(dining.lead(expiring: [anyID]), .endsSoon)
        XCTAssertEqual(dining.lead(), .bestWith("Test Bank Solo"), "…and only when it is actually expiring")
    }

    func testAnExpiringIDFromAnotherShelfIsIgnored() throws {
        let wallet = [card("Solo", dining: 4, groceries: 2)]
        let dining = try shelf(.dining, in: wallet)
        let groceriesID = try XCTUnwrap(shelf(.groceries, in: wallet).benefits.first?.id)

        XCTAssertEqual(dining.lead(expiring: [groceriesID]), .bestWith("Test Bank Solo"))
    }

    // MARK: - The words

    /// Every case has to produce a sentence. A blank third line is the state
    /// this whole type was introduced to remove.
    func testEveryLeadSaysSomething() {
        let all: [BenefitGroupSummary.Lead] = [
            .endsSoon,
            .needsSwitchingOn,
            .bestWith("Amex Gold"),
            .severalCards(3),
            .nothingPaying
        ]
        for lead in all {
            XCTAssertFalse(lead.text.isEmpty, "\(lead) has no words")
        }
    }

    /// The two that mean "do something" are the two that get the colour, and
    /// both say so in words as well — colour is never the only signal.
    func testOnlyTheActionableOnesAskForAttention() {
        XCTAssertTrue(BenefitGroupSummary.Lead.endsSoon.needsAttention)
        XCTAssertTrue(BenefitGroupSummary.Lead.needsSwitchingOn.needsAttention)
        XCTAssertFalse(BenefitGroupSummary.Lead.bestWith("X").needsAttention)
        XCTAssertFalse(BenefitGroupSummary.Lead.severalCards(2).needsAttention)
        XCTAssertFalse(BenefitGroupSummary.Lead.nothingPaying.needsAttention)
    }

    func testTheCardNameIsInTheWords() {
        XCTAssertTrue(BenefitGroupSummary.Lead.bestWith("Amex Gold").text.contains("Amex Gold"))
    }

    // MARK: - Nothing at all

    func testAShelfWithNothingActiveSaysSo() {
        let empty = BenefitGroupSummary(group: .dining, benefits: [])
        XCTAssertEqual(empty.lead(), .nothingPaying)
    }
}
