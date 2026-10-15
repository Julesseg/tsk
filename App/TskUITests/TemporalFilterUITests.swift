import XCTest

final class TemporalFilterUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testSavedReadyDeadlineViewReevaluatesNextDayAndCompletion() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_NOW"] = "1792058400"
        app.launch()
        XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 10))
        app.buttons["new-task"].tap()
        let description = app.textFields["task-description"].exists ? app.textFields["task-description"] : app.textViews["task-description"]
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        description.tap()
        description.typeText("Relative deadline")
        setDateSwitch("deadline-enabled", to: true, app: app)
        app.buttons["save-task"].tap()
        XCTAssertTrue(app.staticTexts["Relative deadline"].waitForExistence(timeout: 10))
        app.buttons["custom-views"].tap()
        app.buttons["new-custom-view"].tap()
        let name = app.textFields["custom-view-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Ready today")
        let expression = app.textViews["raw-filter-expression"]
        XCTAssertTrue(revealTaskElement(expression, in: "raw-filter-form", app: app))
        expression.tap()
        expression.typeText("due:today and +READY")
        let done = app.buttons["dismiss-filter-keyboard"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        app.buttons["save-custom-view"].tap()
        XCTAssertTrue(app.buttons["active-custom-view"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Relative deadline"].exists)
        capture("Relative deadline and READY saved view", app: app)
        app.terminate()
        app.launchEnvironment["TSK_TEST_NOW"] = "1792144800"
        app.launch()
        openSavedView(app)
        XCTAssertTrue(app.staticTexts["No matching tasks"].waitForExistence(timeout: 10))
        capture("Same saved expression after the day changes", app: app)
        app.terminate()
        app.launchEnvironment["TSK_TEST_NOW"] = "1792058400"
        app.launch()
        openSavedView(app)
        XCTAssertTrue(app.staticTexts["Relative deadline"].waitForExistence(timeout: 10))
        app.staticTexts["Relative deadline"].tap()
        XCTAssertTrue(revealTaskElement(app.buttons["complete-task"], in: "task-detail-form", app: app))
        app.buttons["complete-task"].tap()
        XCTAssertTrue(app.staticTexts["task-detail-status"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["task-detail-status"].label.contains("Completed"))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["No matching tasks"].waitForExistence(timeout: 10))
        capture("Completing a result reevaluates the READY expression", app: app)
    }

    private func openSavedView(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["custom-views"].waitForExistence(timeout: 10))
        app.buttons["custom-views"].tap()
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "saved-view-")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertTrue(saved.label.contains("Ready today"))
        saved.tap()
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
