import XCTest

@MainActor
final class TskWaitingUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testWaitingTaskStaysInTodayAndWaitExpiresOrClearsWithoutChangingPlanning() throws {
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_NOW"] = "1791972000"
        app.launch()
        XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 10))
        app.buttons["new-task"].tap()
        let description = app.textFields["task-description"].exists ? app.textFields["task-description"] : app.textViews["task-description"]
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        description.tap()
        description.typeText("Planned task waiting for tomorrow")
        setDateSwitch("planned-day-enabled", to: true, app: app)
        setDateSwitch("deadline-enabled", to: true, app: app)
        setDateSwitch("waiting-date-enabled", to: true, app: app)
        capture("Independent native waiting-date editor", app: app)
        app.buttons["save-task"].tap()
        XCTAssertTrue(app.staticTexts["Planned task waiting for tomorrow"].waitForExistence(timeout: 10))
        selectToday(app)
        XCTAssertTrue(waitingReasons(app).firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Planned task waiting for tomorrow"].exists)
        capture("Matching waiting task remains in Today with reason", app: app)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 10))
        selectToday(app)
        XCTAssertTrue(waitingReasons(app).firstMatch.waitForExistence(timeout: 10))
        app.staticTexts["Planned task waiting for tomorrow"].tap()
        XCTAssertTrue(app.staticTexts["task-detail-status"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["task-detail-status"].label.contains("Pending"))
        XCTAssertTrue(waitingReasons(app).firstMatch.exists)
        capture("Pending detail with waiting reason and separate planning dates", app: app)
        app.terminate()
        app.launchEnvironment["TSK_TEST_NOW"] = "1792058400"
        app.launch()
        XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 10))
        selectToday(app)
        XCTAssertTrue(app.staticTexts["Planned task waiting for tomorrow"].waitForExistence(timeout: 10))
        XCTAssertEqual(waitingReasons(app).count, 0)
        capture("Wait expiry removes reason while carried-forward task remains", app: app)
        app.staticTexts["Planned task waiting for tomorrow"].tap()
        app.buttons["edit-task"].tap()
        setDateSwitch("waiting-date-enabled", to: false, app: app)
        setDateSwitch("waiting-date-enabled", to: true, app: app)
        app.buttons["save-task"].tap()
        XCTAssertTrue(app.buttons["edit-task"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(waitingReasons(app).firstMatch.waitForExistence(timeout: 10))
        capture("Editing wait reintroduces reason without removing Today task", app: app)
        app.staticTexts["Planned task waiting for tomorrow"].tap()
        app.buttons["edit-task"].tap()
        setDateSwitch("waiting-date-enabled", to: false, app: app)
        app.buttons["save-task"].tap()
        XCTAssertTrue(app.buttons["edit-task"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["Planned task waiting for tomorrow"].waitForExistence(timeout: 10))
        XCTAssertEqual(waitingReasons(app).count, 0)
        capture("Clearing wait leaves planned and due task visible", app: app)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 10))
        selectToday(app)
        XCTAssertTrue(app.staticTexts["Planned task waiting for tomorrow"].waitForExistence(timeout: 10))
        XCTAssertEqual(waitingReasons(app).count, 0)
    }

    private func selectToday(_ app: XCUIApplication) {
        app.segmentedControls["task-status-view"].buttons["Today"].tap()
    }

    private func waitingReasons(_ app: XCUIApplication) -> XCUIElementQuery {
        app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "task-waiting-reason-"))
    }


    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
