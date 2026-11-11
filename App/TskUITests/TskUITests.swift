import XCTest

@MainActor
final class TskUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testCaptureReviewCancelSaveAndRelaunch() throws {
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 10))
        screenshot("Tasks empty", app: app)
        app.buttons["New task"].tap()
        let description = app.descendants(matching: .any).matching(identifier: "task-description").firstMatch
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Cancel"].exists)
        let captureCell = app.cells.containing(.any, identifier: "task-description").firstMatch
        XCTAssertGreaterThanOrEqual(captureCell.frame.minY, app.navigationBars["Today"].frame.maxY, "The draft card must stay below the navigation header")
        XCTAssertTrue(app.tabBars.buttons["Today"].isSelected)
        tapTaskControl(app.buttons["collapse-task-row"], app: app)
        XCTAssertTrue(description.waitForNonExistence(timeout: 5))
        app.buttons["New task"].tap()
        let reviewedDescription = app.descendants(matching: .any)["task-description"].firstMatch
        XCTAssertTrue(reviewedDescription.waitForExistence(timeout: 5))
        reviewedDescription.typeText("Buy milk from the market")
        tapTaskControlAtCenter(app.buttons["dismiss-row-keyboard"], app: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(captureCell.frame.minY, app.navigationBars["Today"].frame.maxY, "Hiding the keyboard must keep the draft below the navigation header")
        tapTaskControl(app.buttons["New task"], app: app)
        XCTAssertEqual(reviewedDescription.value as? String, "Buy milk from the market")
        screenshot("Draft review", app: app)
        taskEditorSaveButton(app).tap()
        XCTAssertTrue(taskRow(named: "Buy milk from the market", app: app).waitForExistence(timeout: 10))
        screenshot("Tasks saved", app: app)
        app.terminate()
        app.launch()
        selectAllTasks(app)
        XCTAssertTrue(taskRow(named: "Buy milk from the market", app: app).waitForExistence(timeout: 10))
        screenshot("Tasks after relaunch", app: app)
        openTaskInformation(taskRow(named: "Buy milk from the market", app: app), app: app)
        let savedDescription = app.staticTexts["task-detail-description"]
        XCTAssertTrue(savedDescription.waitForExistence(timeout: 5))
        XCTAssertEqual(savedDescription.label, "Buy milk from the market")
        XCTAssertTrue(app.descendants(matching: .any)["task-detail-status"].label.contains("Pending"))
        XCTAssertFalse(app.staticTexts["Identity"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "raw-attribute-")).firstMatch.exists)
        screenshot("Saved task information after relaunch", app: app)
    }

    private func screenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
