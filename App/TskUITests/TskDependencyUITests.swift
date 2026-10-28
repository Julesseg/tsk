import XCTest

@MainActor
final class TskDependencyUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testDependencySelectionCycleFailureCompletionAndRemovalPersistInToday() throws {
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_NOW"] = "1791972000"
        app.launch()
        captureTask("Prerequisite outside Today", planned: false, waiting: false, app: app)
        captureTask("Planned dependent", planned: true, waiting: true, app: app)
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(taskRow(named: "Planned dependent", app: app).waitForExistence(timeout: 10))
        XCTAssertFalse(taskRow(named: "Prerequisite outside Today", app: app).exists)
        openTaskInformation(taskRow(named: "Planned dependent", app: app), app: app)
        tap(app.buttons["add-dependency"], in: app)
        let candidate = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "dependency-candidate-")).firstMatch
        XCTAssertTrue(candidate.waitForExistence(timeout: 5))
        XCTAssertTrue(candidate.label.contains("Prerequisite outside Today"))
        let targetIdentity = candidate.identifier.suffix(36)
        screenshot("Native prerequisite selection with stable identity", app: app)
        candidate.tap()
        XCTAssertTrue(app.buttons["add-dependency"].waitForExistence(timeout: 10))
        app.swipeDown()
        app.swipeDown()
        XCTAssertTrue(blockedReasons(app).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(waitingReasons(app).firstMatch.exists)
        screenshot("Waiting and blocked reasons coexist", app: app)
        let prerequisiteLink = app.buttons["dependency-task-\(targetIdentity)"]
        tap(prerequisiteLink, in: app)
        tap(app.buttons["add-dependency"], in: app)
        let cycleCandidate = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "dependency-candidate-")).firstMatch
        XCTAssertTrue(cycleCandidate.waitForExistence(timeout: 5))
        cycleCandidate.tap()
        XCTAssertTrue(app.staticTexts["dependency-selection-error"].waitForExistence(timeout: 10))
        screenshot("Cycle rejected without saving another link", app: app)
        app.buttons["Cancel"].tap()
        tap(app.buttons["complete-task"], in: app)
        XCTAssertTrue(app.buttons["complete-task"].waitForNonExistence(timeout: 2))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.swipeDown()
        app.swipeDown()
        XCTAssertEqual(blockedReasons(app).count, 0)
        XCTAssertTrue(waitingReasons(app).firstMatch.waitForExistence(timeout: 5))
        screenshot("Prerequisite completion clears only blocked reason", app: app)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(taskRow(named: "Planned dependent", app: app).waitForExistence(timeout: 10))
        XCTAssertEqual(blockedReasons(app).count, 0)
        openTaskInformation(taskRow(named: "Planned dependent", app: app), app: app)
        tap(app.buttons["dependency-task-\(targetIdentity)"], in: app)
        XCTAssertTrue(app.staticTexts["task-detail-status"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["task-detail-status"].label.contains("Completed"))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let remove = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "remove-dependency-")).firstMatch
        tap(remove, in: app)
        XCTAssertTrue(app.staticTexts["No prerequisites"].waitForExistence(timeout: 5))
        screenshot("Explicit dependency removal preserves planned task", app: app)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Today"].tap()
        openTaskInformation(taskRow(named: "Planned dependent", app: app), app: app)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "dependency-task-")).firstMatch.exists)
        tap(app.buttons["add-dependency"], in: app)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "dependency-candidate-")).firstMatch.waitForExistence(timeout: 5))
    }

    private func captureTask(_ description: String, planned: Bool, waiting: Bool, app: XCUIApplication) {
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 10))
        app.buttons["New task"].tap()
        let field = app.textFields["task-description"].exists ? app.textFields["task-description"] : app.textViews["task-description"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(description)
        if planned { setDateSwitch("planned-day-enabled", to: true, app: app) }
        if waiting { setDateSwitch("waiting-date-enabled", to: true, app: app) }
        app.buttons["save-task"].tap()
        XCTAssertTrue(taskRow(named: description, app: app).waitForExistence(timeout: 10))
    }

    private func tap(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(revealTaskElement(element, in: "task-detail-form", app: app))
        element.tap()
    }

    private func blockedReasons(_ app: XCUIApplication) -> XCUIElementQuery {
        app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "task-blocked-reason-"))
    }

    private func waitingReasons(_ app: XCUIApplication) -> XCUIElementQuery {
        app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "task-waiting-reason-"))
    }

    private func screenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
