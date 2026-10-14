import XCTest

final class TskUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testCaptureReviewCancelSaveAndRelaunch() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 10))
        screenshot("Tasks empty", app: app)
        app.buttons["new-task"].tap()
        let description = app.textFields["task-description"].exists ? app.textFields["task-description"] : app.textViews["task-description"]
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        description.tap()
        description.typeText("Cancelled capture")
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.staticTexts["Cancelled capture"].exists)
        app.buttons["new-task"].tap()
        app.buttons["save-task"].tap()
        XCTAssertTrue(app.staticTexts["draft-error"].waitForExistence(timeout: 5))
        screenshot("Draft validation", app: app)
        let reviewedDescription = app.textFields["task-description"].exists ? app.textFields["task-description"] : app.textViews["task-description"]
        reviewedDescription.tap()
        reviewedDescription.typeText("Buy milk from the market")
        screenshot("Draft review", app: app)
        app.buttons["save-task"].tap()
        XCTAssertTrue(app.staticTexts["Buy milk from the market"].waitForExistence(timeout: 10))
        screenshot("Tasks saved", app: app)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Buy milk from the market"].waitForExistence(timeout: 10))
        screenshot("Tasks after relaunch", app: app)
        app.staticTexts["Buy milk from the market"].tap()
        XCTAssertTrue(app.staticTexts["Identity"].waitForExistence(timeout: 5))
        screenshot("Raw attributes and identity", app: app)
    }

    func testDescriptionEditAndCompletionPersistAcrossRelaunch() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 10))
        app.buttons["new-task"].tap()
        let field = app.textFields["task-description"].exists ? app.textFields["task-description"] : app.textViews["task-description"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Original task")
        app.buttons["save-task"].tap()
        XCTAssertTrue(app.staticTexts["Original task"].waitForExistence(timeout: 10))
        app.staticTexts["Original task"].tap()
        app.buttons["edit-task"].tap()
        let editor = app.textFields["task-description"].exists ? app.textFields["task-description"] : app.textViews["task-description"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeText(" revised")
        screenshot("Edited draft", app: app)
        app.buttons["save-task"].tap()
        XCTAssertTrue(app.staticTexts["Original task revised"].waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Original task revised"].waitForExistence(timeout: 10))
        screenshot("Edited task after relaunch", app: app)
        app.staticTexts["Original task revised"].tap()
        XCTAssertTrue(app.buttons["complete-task"].waitForExistence(timeout: 5))
        app.buttons["complete-task"].tap()
        XCTAssertFalse(app.buttons["complete-task"].waitForExistence(timeout: 2))
        screenshot("Completed detail", app: app)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Original task revised"].exists)
        app.segmentedControls["task-status-view"].buttons["Completed"].tap()
        XCTAssertTrue(app.staticTexts["Original task revised"].waitForExistence(timeout: 10))
        screenshot("Completed list after relaunch", app: app)
    }

    func testOrganizationProjectViewsAndListActionsPersist() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 10))
        app.buttons["new-task"].tap()
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
        XCTAssertTrue(app.staticTexts["Project fixture"].waitForExistence(timeout: 10))
        app.buttons["project-filter"].tap()
        app.buttons["Work"].tap()
        XCTAssertTrue(app.staticTexts["Project fixture"].waitForExistence(timeout: 5))
        screenshot("Exact project view", app: app)
        app.staticTexts["Project fixture"].tap()
        app.buttons["edit-task"].tap()
        let editedProject = app.textFields["task-project"]
        XCTAssertTrue(editedProject.waitForExistence(timeout: 5))
        editedProject.doubleTap()
        editedProject.typeText("Work.sub")
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
        XCTAssertTrue(app.buttons["project-filter"].waitForExistence(timeout: 10))
        app.buttons["project-filter"].tap()
        app.buttons["Work.sub"].tap()
        XCTAssertTrue(app.staticTexts["Project fixture"].waitForExistence(timeout: 5))
        screenshot("Organization after relaunch", app: app)
        app.staticTexts["Project fixture"].swipeLeft()
        app.buttons["Complete"].tap()
        XCTAssertFalse(app.staticTexts["Project fixture"].waitForExistence(timeout: 2))
        app.segmentedControls["task-status-view"].buttons["Completed"].tap()
        XCTAssertTrue(app.staticTexts["Project fixture"].waitForExistence(timeout: 10))
        screenshot("Completed task in project view", app: app)
    }

    private func screenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
