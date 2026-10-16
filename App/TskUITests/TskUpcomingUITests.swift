import XCTest

@MainActor
final class TskUpcomingUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testFutureDateRolesShareTaskIdentityAndActionsAcrossDayGroups() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_NOW"] = "1792144800"
        app.launch()
        XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 10))
        app.segmentedControls["task-status-view"].buttons["Upcoming"].tap()
        XCTAssertTrue(app.staticTexts["No upcoming plans or deadlines"].waitForExistence(timeout: 5))
        capture("Upcoming empty", app: app)
        app.buttons["new-task"].tap()
        let description = app.textFields["task-description"].exists ? app.textFields["task-description"] : app.textViews["task-description"]
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        description.tap()
        description.typeText("One task two future dates")
        setDateSwitch("planned-day-enabled", to: true, app: app)
        setDateSwitch("deadline-enabled", to: true, app: app)
        app.buttons["save-task"].tap()
        XCTAssertTrue(app.staticTexts["One task two future dates"].waitForExistence(timeout: 10))
        app.terminate()
        app.launchEnvironment["TSK_TEST_NOW"] = "1791972000"
        app.launch()
        XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 10))
        selectUpcoming(app)
        XCTAssertTrue(plannedRows(app).firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(plannedRows(app).count, 1)
        XCTAssertEqual(deadlineRows(app).count, 1)
        XCTAssertEqual(dayHeaders(app).count, 1)
        let plannedIdentity = plannedRows(app).firstMatch.identifier.suffix(36)
        let deadlineIdentity = deadlineRows(app).firstMatch.identifier.suffix(36)
        XCTAssertEqual(plannedIdentity, deadlineIdentity)
        capture("Same-day planned work and deadline with one task identity", app: app)
        plannedRows(app).firstMatch.tap()
        XCTAssertTrue(app.buttons["edit-task"].waitForExistence(timeout: 5))
        app.buttons["edit-task"].tap()
        tapButton("plan-tomorrow", app: app)
        app.buttons["save-task"].tap()
        XCTAssertTrue(app.buttons["edit-task"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(plannedRows(app).firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(dayHeaders(app).count, 2)
        XCTAssertEqual(plannedRows(app).firstMatch.identifier.suffix(36), plannedIdentity)
        XCTAssertEqual(deadlineRows(app).firstMatch.identifier.suffix(36), plannedIdentity)
        capture("Task planned tomorrow with deadline on following day", app: app)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 10))
        selectUpcoming(app)
        XCTAssertTrue(plannedRows(app).firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(dayHeaders(app).count, 2)
        XCTAssertEqual(deadlineRows(app).count, 1)
        plannedRows(app).firstMatch.swipeLeft()
        XCTAssertTrue(app.buttons["Complete"].waitForExistence(timeout: 5))
        app.buttons["Complete"].tap()
        XCTAssertTrue(app.staticTexts["No upcoming plans or deadlines"].waitForExistence(timeout: 10))
        capture("Upcoming completion removes all task appearances", app: app)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 10))
        selectUpcoming(app)
        XCTAssertTrue(app.staticTexts["No upcoming plans or deadlines"].waitForExistence(timeout: 10))
        app.segmentedControls["task-status-view"].buttons["Completed"].tap()
        XCTAssertTrue(app.staticTexts["One task two future dates"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts.matching(identifier: "One task two future dates").count, 1)
    }

    private func selectUpcoming(_ app: XCUIApplication) {
        app.segmentedControls["task-status-view"].buttons["Upcoming"].tap()
    }

    private func plannedRows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "upcoming-planned-"))
    }

    private func deadlineRows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "upcoming-deadline-"))
    }

    private func dayHeaders(_ app: XCUIApplication) -> XCUIElementQuery {
        app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "upcoming-day-"))
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
