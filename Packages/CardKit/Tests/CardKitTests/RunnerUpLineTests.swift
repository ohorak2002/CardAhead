import XCTest
@testable import CardKit

/// The sentence that stops a recommendation saying the same thing three times.
///
/// **Cards are built here rather than taken from `CardCatalog`.** A test that
/// asserts "4x" against a real product fails the day the issuer re-prices it,
/// and the thing under test is the comparison, not the rate — this repo has
/// burned two CI runs on exactly that mistake. Built cards pin the behaviour.
final class RunnerUpLineTests: XCTestCase {

    private let engine = RecommendationEngine()

    private func context(_ category: SpendingCategory) -> PurchaseContext {
        PurchaseContext(category: category, confidence: .exact, date: Fixture.inQ3)
    }

    private func card(_ name: String, dining: Double, base: Double = 1) -> Card {
        Card(
            issuer: "Test Bank",
            name: name,
            currency: RewardCurrency(name: "Test points", centsPerUnit: 1, style: .multiplier),
            rules: [
                CategoryRule(category: .dining, rate: dining),
                CategoryRule(category: .base, rate: base)
            ]
        )
    }

    // MARK: - The ordinary case

    func testItNamesTheRunnerUpAndItsRate() throws {
        let wallet = [card("Winner", dining: 4), card("Runner Up", dining: 2)]
        let recommendation = try XCTUnwrap(engine.recommend(from: wallet, in: context(.dining)))

        let line = try XCTUnwrap(recommendation.runnerUpLine)
        XCTAssertTrue(line.contains("Runner Up"), line)
        XCTAssertFalse(line.contains("Winner"), "the winner is already named twice above this line")
    }

    /// The whole point of the line: it carries a number the other two lines do
    /// not, so it has to actually contain one.
    func testItCarriesTheOtherCardsRate() throws {
        let wallet = [card("Winner", dining: 4), card("Runner Up", dining: 2)]
        let recommendation = try XCTUnwrap(engine.recommend(from: wallet, in: context(.dining)))
        let line = try XCTUnwrap(recommendation.runnerUpLine)
        XCTAssertTrue(line.contains("2"), line)
    }

    // MARK: - When there is nothing to say

    /// One card is not a comparison. A sentence here would have to invent a
    /// second card or say something empty.
    func testAWalletOfOneHasNoRunnerUp() throws {
        let recommendation = try XCTUnwrap(
            engine.recommend(from: [card("Only", dining: 4)], in: context(.dining))
        )
        XCTAssertNil(recommendation.runnerUpLine)
    }

    /// **Two cards paying the same rate is the case worth being careful
    /// about.** There is a runner-up, the ranking did separate them (on a
    /// tiebreak), and the sentence would read "your next best card is X, at
    /// 4x" directly under "4x points with Y" — which tells the reader the
    /// choice did not matter, in the voice of a recommendation. Nil is the
    /// honest answer.
    func testATieProducesNoLine() throws {
        let wallet = [card("One", dining: 4), card("Two", dining: 4)]
        let recommendation = try XCTUnwrap(engine.recommend(from: wallet, in: context(.dining)))
        XCTAssertNil(recommendation.runnerUpLine)
    }

    func testAnEmptyWalletRecommendsNothingAtAll() {
        XCTAssertNil(engine.recommend(from: [], in: context(.dining)))
    }

    // MARK: - It is a sentence

    func testItReadsAsOne() throws {
        let wallet = [card("Winner", dining: 4), card("Runner Up", dining: 2)]
        let line = try XCTUnwrap(
            engine.recommend(from: wallet, in: context(.dining))?.runnerUpLine
        )
        XCTAssertTrue(line.hasSuffix("."), line)
        XCTAssertTrue(line.hasPrefix("Your next best card"), line)
    }

    /// It sits under `rewardLine`, which already names the winner and its
    /// rate. Repeating either is the duplication this line exists to end.
    func testItDoesNotRepeatTheWinnersRate() throws {
        let wallet = [card("Winner", dining: 5), card("Runner Up", dining: 2)]
        let recommendation = try XCTUnwrap(engine.recommend(from: wallet, in: context(.dining)))
        let line = try XCTUnwrap(recommendation.runnerUpLine)
        let winnersRate = recommendation.best.card.currency.formatted(
            rate: recommendation.best.appliedRate
        )
        XCTAssertFalse(line.contains(winnersRate), "\(line) repeats the winner's \(winnersRate)")
    }
}
