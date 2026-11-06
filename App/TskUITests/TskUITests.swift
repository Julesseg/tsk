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

    func testOrganizationProjectViewsAndListActionsPersist() throws {
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 10))
        app.buttons["New task"].tap()
        let description = app.descendants(matching: .any).matching(identifier: "task-description").firstMatch
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        description.typeText("Project fixture")
        setCaptureProject("Work", app: app)
        openTaskRowParameter("priority", app: app)
        app.buttons["High"].tap()
        openTaskRowParameter("tags", app: app)
        let tag = app.textFields["row-tag-input"]
        XCTAssertTrue(tag.waitForExistence(timeout: 5))
        tag.tap()
        tag.typeText("home")
        tapTaskControl(app.buttons["close-row-parameter"], app: app)
        screenshot("Organization draft", app: app)
        taskEditorSaveButton(app).tap()
        XCTAssertTrue(taskRow(named: "Project fixture", app: app).waitForExistence(timeout: 10))
        app.tabBars.buttons["Projects"].tap()
        app.buttons["project-Work"].tap()
        XCTAssertTrue(taskRow(named: "Project fixture", app: app).waitForExistence(timeout: 5))
        screenshot("Exact project view", app: app)
        app.buttons["New task"].tap()
        let inheritedTitle = app.descendants(matching: .any)["task-description"].firstMatch
        XCTAssertTrue(inheritedTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["row-project"].value as? String, "Work")
        XCTAssertEqual(app.buttons["row-scheduled"].value as? String, "Not set")
        inheritedTitle.typeText("Project capture")
        taskEditorSaveButton(app).tap()
        XCTAssertTrue(taskRow(named: "Project capture", app: app).waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Work"].exists)
        screenshot("Project capture inherits an editable default", app: app)
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
        taskEditorSaveButton(app).tap()
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
