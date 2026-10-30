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
        let description = app.textFields["task-description"].exists ? app.textFields["task-description"] : app.textViews["task-description"]
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        description.tap()
        description.typeText("Cancelled capture")
        app.buttons["Cancel"].tap()
        XCTAssertFalse(taskRow(named: "Cancelled capture", app: app).exists)
        app.buttons["New task"].tap()
        app.buttons["save-task"].tap()
        XCTAssertTrue(app.staticTexts["draft-error"].waitForExistence(timeout: 5))
        screenshot("Draft validation", app: app)
        let reviewedDescription = app.textFields["task-description"].exists ? app.textFields["task-description"] : app.textViews["task-description"]
        reviewedDescription.tap()
        reviewedDescription.typeText("Buy milk from the market")
        screenshot("Draft review", app: app)
        app.buttons["save-task"].tap()
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

    func testOrganizationProjectViewsAndListActionsPersist() throws {
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 10))
        app.buttons["New task"].tap()
        let description = app.textFields["task-description"].exists ? app.textFields["task-description"] : app.textViews["task-description"]
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        description.typeText("Project fixture")
        let project = app.textFields["task-project"]
        project.tap()
        project.typeText("Work")
        app.buttons["task-priority"].tap()
        app.buttons["High"].tap()
        let tag = app.textFields["task-tag-input"]
        tag.tap()
        tag.typeText("home")
        app.buttons["add-tag"].tap()
        screenshot("Organization draft", app: app)
        app.buttons["save-task"].tap()
        XCTAssertTrue(taskRow(named: "Project fixture", app: app).waitForExistence(timeout: 10))
        app.tabBars.buttons["Projects"].tap()
        app.buttons["project-Work"].tap()
        XCTAssertTrue(taskRow(named: "Project fixture", app: app).waitForExistence(timeout: 5))
        screenshot("Exact project view", app: app)
        openTaskInformation(taskRow(named: "Project fixture", app: app), app: app)
        app.buttons["edit-task"].tap()
        let editedProject = app.textFields["task-project"]
        XCTAssertTrue(editedProject.waitForExistence(timeout: 5))
        replaceTaskText(editedProject, with: "Work.sub", app: app)
        XCTAssertEqual(editedProject.value as? String, "Work.sub")
        app.buttons["task-priority"].tap()
        app.buttons["Low"].tap()
        app.buttons["remove-tag-home"].tap()
        let editedTag = app.textFields["task-tag-input"]
        editedTag.tap()
        editedTag.typeText("next")
        app.buttons["save-task"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Projects"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Projects"].tap()
        app.buttons["project-Work.sub"].tap()
        XCTAssertTrue(taskRow(named: "Project fixture", app: app).waitForExistence(timeout: 5))
        screenshot("Organization after relaunch", app: app)
        let completionID = String(taskRow(named: "Project fixture", app: app).identifier.dropFirst(5))
        app.buttons["complete-task-row-" + completionID].tap()
        XCTAssertTrue(taskRow(named: "Project fixture", app: app).waitForNonExistence(timeout: 2))
        selectDoneTasks(app)
        XCTAssertTrue(taskRow(named: "Project fixture", app: app).waitForExistence(timeout: 10))
        screenshot("Completed task in project view", app: app)
    }

    private func screenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
