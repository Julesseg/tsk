import XCTest

@MainActor
final class TskPlanningUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testIndependentDatesCarryForwardRescheduleAndCompleteInToday() throws {
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_NOW"] = "1791972000"
        app.launch()
        XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 10))
        app.buttons["new-task"].tap()
        enterDescription("Planned and due independently", app: app)
        setDateSwitch("planned-day-enabled", to: true, app: app)
        setDateSwitch("deadline-enabled", to: true, app: app)
        capture("Independent planned day and deadline editors", app: app)
        app.buttons["save-task"].tap()
        XCTAssertTrue(app.staticTexts["Planned and due independently"].waitForExistence(timeout: 10))
        selectToday(app)
        XCTAssertTrue(app.staticTexts["Planned and due independently"].waitForExistence(timeout: 10))
        capture("Today planned and due task", app: app)
        app.terminate()
        app.launchEnvironment["TSK_TEST_NOW"] = "1792058400"
        app.launch()
        XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 10))
        selectToday(app)
        XCTAssertTrue(app.staticTexts["Planned and due independently"].waitForExistence(timeout: 10))
        capture("Next day carried forward and overdue", app: app)
        taskRow(named: "Planned and due independently", app: app).tap()
        XCTAssertTrue(app.buttons["edit-task"].waitForExistence(timeout: 10))
        XCTAssertTrue(revealTaskElement(app.descendants(matching: .any)["task-planned-day"].firstMatch, in: "task-detail-form", app: app))
        app.buttons["edit-task"].tap()
        tapButton("plan-tomorrow", app: app)
        app.buttons["save-task"].tap()
        XCTAssertTrue(app.buttons["edit-task"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["Planned and due independently"].waitForExistence(timeout: 10))
        taskRow(named: "Planned and due independently", app: app).tap()
        XCTAssertTrue(app.buttons["edit-task"].waitForExistence(timeout: 10))
        app.buttons["edit-task"].tap()
        setDateSwitch("deadline-enabled", to: false, app: app)
        app.buttons["save-task"].tap()
        XCTAssertTrue(app.buttons["edit-task"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertFalse(app.staticTexts["Planned and due independently"].waitForExistence(timeout: 2))
        capture("Rescheduled beyond Today with deadline removed", app: app)
        app.tabBars.buttons["Unfinished"].tap()
        XCTAssertTrue(app.staticTexts["Planned and due independently"].waitForExistence(timeout: 10))
        taskRow(named: "Planned and due independently", app: app).tap()
        XCTAssertTrue(app.buttons["edit-task"].waitForExistence(timeout: 10))
        app.buttons["edit-task"].tap()
        tapButton("plan-today", app: app)
        app.buttons["save-task"].tap()
        XCTAssertTrue(app.buttons["edit-task"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        selectToday(app)
        XCTAssertTrue(app.staticTexts["Planned and due independently"].waitForExistence(timeout: 10))
        app.staticTexts["Planned and due independently"].swipeLeft()
        XCTAssertTrue(app.buttons["Complete"].waitForExistence(timeout: 5))
        app.buttons["Complete"].tap()
        XCTAssertFalse(app.staticTexts["Planned and due independently"].waitForExistence(timeout: 2))
        capture("Completed task leaves Today immediately", app: app)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 10))
        selectToday(app)
        XCTAssertFalse(app.staticTexts["Planned and due independently"].exists)
    }

    private func selectToday(_ app: XCUIApplication) {
        app.tabBars.buttons["Today"].tap()
    }

    private func enterDescription(_ text: String, app: XCUIApplication) {
        let field = app.textFields["task-description"].exists ? app.textFields["task-description"] : app.textViews["task-description"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)
    }


    private func tapButton(_ identifier: String, app: XCUIApplication) {
        let control = app.buttons[identifier]
        for _ in 0..<4 where !control.isHittable { app.swipeUp() }
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        control.tap()
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
