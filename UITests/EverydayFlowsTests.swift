import XCTest

/// These tests operate only the isolated DemoSeed wallet on the CI simulator.
final class EverydayFlowsTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testAllOffRemainsNoneThroughSearchAndCancel() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-CardWiseDemoSeed", "-CardWiseDemoTab", "mapfilters"]
        app.launch()
        let all = app.buttons["All"].firstMatch
        XCTAssertTrue(all.waitForExistence(timeout: 15))
        if !all.isSelected { all.tap() }
        all.tap()
        XCTAssertFalse(all.isSelected)
        app.buttons["Apply filters"].tap()
        let empty = app.staticTexts["Select a category to see nearby places"].firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
        let search = app.textFields["Search places, stores or categories"]
        search.tap(); search.typeText("coffee\n")
        XCTAssertTrue(empty.exists)
        app.buttons["Clear search"].tap()
        XCTAssertTrue(empty.exists)
        app.buttons["Filters"].tap()
        app.buttons["Restaurants"].firstMatch.tap()
        app.buttons["Cancel"].tap()
        XCTAssertTrue(empty.exists)
    }

    @MainActor
    func testOfferGuidanceCanBeCancelledWithoutSaving() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-CardWiseDemoSeed", "-CardWiseDemoTab", "benefits"]
        app.launch()
        let add = app.buttons["Add a reward or offer"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 15))
        add.tap()
        XCTAssertTrue(app.textFields["Name this offer"].waitForExistence(timeout: 5))
        app.textFields["Name this offer"].tap()
        app.textFields["Name this offer"].typeText("Unsaved test offer")
        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["What do you get?"].exists || app.staticTexts["WHAT DO YOU GET?"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Unsaved test offer"].exists)
    }

    @MainActor
    func testNicknamePreferenceSurvivesRelaunch() throws {
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
        XCTAssertTrue(hidden.exists)
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

    /// A decimal pad has no return key, so without the keyboard toolbar there
    /// is nothing on screen that puts it away.
    @MainActor
    func testAmountFieldOffersAWayOffTheKeyboard() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-CardWiseDemoSeed", "-CardWiseDemoTab", "today"]
        app.launch()
        let goal = app.buttons["Edit goal"].firstMatch
        XCTAssertTrue(goal.waitForExistence(timeout: 15))
        goal.tap()
        let field = app.textFields["Monthly goal in US dollars"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 5))
        let done = app.buttons["keyboard.done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(app.keyboards.element.waitForNonExistence(timeout: 5))
    }

    /// A fee field showing the zero it was born with must not turn "95" into
    /// "095" — the zero is a prompt, not something anybody typed.
    @MainActor
    func testAZeroFeeIsReplacedRatherThanTypedInto() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-CardWiseDemoSeed", "-CardWiseDemoTab", "addcard"]
        app.launch()
        let byHand = app.buttons["My card is not on the list"].firstMatch
        XCTAssertTrue(byHand.waitForExistence(timeout: 15))
        for _ in 0..<4 where !byHand.isHittable { app.swipeUp() }
        byHand.tap()
        let fee = app.textFields["Annual fee in dollars"]
        XCTAssertTrue(fee.waitForExistence(timeout: 10))
        for _ in 0..<6 where !fee.isHittable { app.swipeUp() }
        XCTAssertEqual(fee.value as? String, "0")
        fee.tap()
        fee.typeText("95")
        XCTAssertEqual(fee.value as? String, "95")
        app.buttons["keyboard.done"].firstMatch.tap()
        XCTAssertEqual(fee.value as? String, "95")
    }
}
