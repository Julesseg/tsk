import XCTest

@MainActor
final class TaskAutomationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testNativeActionsChangeIndependentDateViewsAndCompletionAfterReopening() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_NOW"] = "1792144800"
        app.launchEnvironment["TSK_TEST_INTENT_DESCRIPTION"] = "Automation dates and completion"
        app.launch()
        XCTAssertTrue(taskRow(named: "Automation dates and completion", app: app).waitForExistence(timeout: 20))
        let row = taskRow(named: "Automation dates and completion", app: app)
        let id = try XCTUnwrap(UUID(uuidString: String(row.identifier.dropFirst(5)))).uuidString
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "TSK_TEST_INTENT_DESCRIPTION")
        app.launchEnvironment["TSK_TEST_INTENT_TARGET_UUID"] = id
        app.launchEnvironment["TSK_TEST_INTENT_ACTION"] = "planned"
        app.launchEnvironment["TSK_TEST_INTENT_DATE"] = "1792224000"
        app.launch()
        choose("Upcoming", sidebar: "upcoming", app: app)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", "upcoming-planned-", id)).firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", "upcoming-deadline-", id)).firstMatch.exists)
        capture("Planned day changed through native intent", app)
        app.terminate()
        app.launchEnvironment["TSK_TEST_INTENT_ACTION"] = "deadline"
        app.launchEnvironment["TSK_TEST_INTENT_DATE"] = "1792314000"
        app.launch()
        choose("Upcoming", sidebar: "upcoming", app: app)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", "upcoming-planned-", id)).firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", "upcoming-deadline-", id)).firstMatch.exists)
        capture("Independent planned day and deadline from native intents", app)
        app.terminate()
        app.launchEnvironment["TSK_TEST_INTENT_ACTION"] = "complete"
        app.launch()
        XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 15))
        choose("Unfinished", sidebar: "unfinished", app: app)
        XCTAssertFalse(taskRow(named: "Automation dates and completion", app: app).exists)
        choose("Completed", sidebar: "completed", app: app)
        XCTAssertTrue(taskRow(named: "Automation dates and completion", app: app).waitForExistence(timeout: 10))
        capture("Native completion visible in completed tasks", app)
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "TSK_TEST_INTENT_ACTION")
        app.launch()
        choose("Completed", sidebar: "completed", app: app)
        XCTAssertTrue(taskRow(named: "Automation dates and completion", app: app).waitForExistence(timeout: 10))
    }

    func testMissingNativeActionReportsFailureAndPreservesPreviouslySavedTask() {
        let app = XCUIApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_INTENT_DESCRIPTION"] = "Keep after rejected action"
        app.launch()
        XCTAssertTrue(taskRow(named: "Keep after rejected action", app: app).waitForExistence(timeout: 20))
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "TSK_TEST_INTENT_DESCRIPTION")
        app.launchEnvironment["TSK_TEST_INTENT_ACTION"] = "complete"
        app.launchEnvironment["TSK_TEST_INTENT_TARGET_UUID"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.staticTexts["Tasks unavailable"].waitForExistence(timeout: 15))
        capture("Missing native action reports its real error", app)
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "TSK_TEST_INTENT_ACTION")
        app.launch()
        XCTAssertTrue(taskRow(named: "Keep after rejected action", app: app).waitForExistence(timeout: 15))
    }

    private func choose(_ title: String, sidebar: String, app: XCUIApplication) {
        XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 15))
        if app.buttons["sidebar-view-" + sidebar].exists { app.buttons["sidebar-view-" + sidebar].tap() }
        else { app.segmentedControls.buttons[title].tap() }
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
