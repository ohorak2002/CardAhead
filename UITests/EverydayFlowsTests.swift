import XCTest

/// These tests operate only the isolated DemoSeed wallet on the CI simulator.
final class EverydayFlowsTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testNicknameAndHiddenPreferenceSurviveRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-CardWiseDemoSeed", "-CardWiseDemoTab", "organize"]
        app.launch()
        let row = app.buttons["organization.card.11111111-1111-4111-8111-111111111111"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()
        let field = app.textFields["card.nickname"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        if let existing = field.value as? String, existing != field.placeholderValue {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        }
        field.typeText("Dinner card")
        let hidden = app.switches["card.hidden"]
        if hidden.value as? String != "1" { hidden.tap() }
        let hiddenOn = NSPredicate(format: "value == '1'")
        expectation(for: hiddenOn, evaluatedWith: hidden)
        waitForExpectations(timeout: 3)
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Dinner card"].exists)
        app.buttons["Done"].tap()
        // The modal dismissal is intentionally not coupled to a particular
        // Wallet row's accessibility timing. The relaunch below is the
        // persistence assertion and also gives SwiftUI time to settle.
        app.terminate()
        app.launch()
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()
        XCTAssertEqual(field.value as? String, "Dinner card")
        XCTAssertEqual(hidden.value as? String, "1")
        // Restore fixture preferences for subsequent runs.
        hidden.tap()
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Dinner card".count))
        app.navigationBars.buttons["Save"].tap()
    }

    @MainActor
    func testComparisonSelectionAndBack() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-CardWiseDemoSeed", "-CardWiseDemoTab", "more"]
        app.launch()
        let compare = app.buttons["Compare cards"]
        XCTAssertTrue(compare.waitForExistence(timeout: 15))
        compare.tap()
        let second = app.buttons["compare.second"]
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        second.tap()
        let cashBack = app.buttons["Everyday cash back"]
        XCTAssertTrue(cashBack.waitForExistence(timeout: 5))
        cashBack.tap()
        XCTAssertTrue(second.label.contains("Everyday cash back") || (second.value as? String)?.contains("Everyday cash back") == true)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(compare.waitForExistence(timeout: 5))
    }

    @MainActor
    func testContextualExplanationOpensAndCloses() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-CardWiseDemoSeed", "-CardWiseDemoTab", "today"]
        app.launch()
        let why = app.buttons["recommendation.why"].firstMatch
        XCTAssertTrue(why.waitForExistence(timeout: 15))
        why.tap()
        XCTAssertTrue(app.navigationBars["Why this card?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["How your cards compare"].exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(why.waitForExistence(timeout: 5))
    }
}
