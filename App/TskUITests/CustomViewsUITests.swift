import XCTest

@MainActor
final class CustomViewsUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testRawViewValidationSaveEditReopenResultsActionsAndDeletion() throws {
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 10))
        app.buttons["new-task"].tap()
        let description = app.textFields["task-description"].exists ? app.textFields["task-description"] : app.textViews["task-description"]
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        description.tap()
        description.typeText("Filter task")
        app.textFields["task-project"].tap()
        app.textFields["task-project"].typeText("Work")
        app.buttons["save-task"].tap()
        XCTAssertTrue(waitForTaskSave(app, row: taskRow(named: "Filter task", app: app), timeout: 10))
        XCTAssertTrue(app.staticTexts["Filter task"].exists)
        app.buttons["custom-views"].tap()
        app.buttons["new-custom-view"].tap()
        let name = app.textFields["custom-view-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Work view")
        let expression = app.textViews["raw-filter-expression"]
        expression.tap()
        expression.typeText("unknown:Work")
        app.buttons["save-custom-view"].tap()
        XCTAssertTrue(app.staticTexts["filter-error"].waitForExistence(timeout: 5))
        XCTAssertEqual(expression.value as? String, "unknown:Work")
        capture("Raw filter schema error", app: app)
        replaceLine(expression, app: app, with: "project.is:Work")
        app.buttons["save-custom-view"].tap()
        XCTAssertTrue(app.buttons["active-custom-view"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Filter task"].exists)
        capture("Custom view real task results", app: app)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["custom-views"].waitForExistence(timeout: 10))
        app.buttons["custom-views"].tap()
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "saved-view-")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertTrue(saved.label.contains("Work view"))
        capture("Saved view after relaunch", app: app)
        saved.swipeLeft()
        app.buttons["Edit"].tap()
        XCTAssertTrue(expression.waitForExistence(timeout: 5))
        XCTAssertEqual(expression.value as? String, "project.is:Work")
        replaceLine(expression, app: app, with: "project.is:Work and status:pending")
        app.buttons["save-custom-view"].tap()
        XCTAssertTrue(app.buttons["active-custom-view"].waitForExistence(timeout: 10))
        app.staticTexts["Filter task"].tap()
        XCTAssertTrue(app.buttons["complete-task"].waitForExistence(timeout: 5))
        app.buttons["complete-task"].tap()
        XCTAssertFalse(app.buttons["complete-task"].waitForExistence(timeout: 2))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["No matching tasks"].waitForExistence(timeout: 10))
        capture("Completion removes task from custom result", app: app)
        app.buttons["custom-views"].tap()
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertFalse(saved.waitForExistence(timeout: 2))
        app.buttons["Done"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["custom-views"].waitForExistence(timeout: 10))
        app.buttons["custom-views"].tap()
        XCTAssertFalse(saved.exists)
    }

    private func replaceLine(_ field: XCUIElement, app: XCUIApplication, with text: String) {
        replaceTaskText(field, with: text, app: app)
        XCTAssertEqual(field.value as? String, text)
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
