import UIKit
import XCTest

@MainActor
final class iPadWorkspaceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad workspace coverage runs in the dedicated iPad lane")
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    override func tearDownWithError() throws { XCUIDevice.shared.orientation = .portrait }

    func testInjectedKeyboardCaptureSelectionEditCompletionAndReopen() throws {
        let app = launch()
        selectDoneTasks(app)
        selectAllTasks(app)
        let commands = try TaskKeyboardCommand(.workspace, app: app)
        XCTAssertTrue(app.tabBars.buttons["All"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.otherElements["workspace-detail-empty"].exists || app.staticTexts["Select a task"].exists)
        capture("iPad landscape empty workspace", app: app)
        try commands.perform("capture") { app.typeKey("n", modifierFlags: .command) }
        let field = description(app)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Keyboard task")
        try commands.perform("saveNew") { app.typeKey(XCUIKeyboardKey.return, modifierFlags: .command) }
        XCTAssertTrue(field.waitForNonExistence(timeout: 10))
        let capturedRow = taskRow(named: "Keyboard task", app: app)
        XCTAssertTrue(capturedRow.waitForExistence(timeout: 10))
        capturedRow.tap()
        XCTAssertTrue(app.buttons["row-scheduled"].waitForExistence(timeout: 5))
        openTaskRowParameter("scheduled", app: app)
        let scheduled = app.datePickers["scheduled-picker"]
        XCTAssertTrue(scheduled.waitForExistence(timeout: 5))
        scheduled.buttons["DatePicker.NextMonth"].tap()
        scheduled.buttons.matching(NSPredicate(format: "label MATCHES %@", "[A-Za-z]+, [A-Za-z]+ 1")).firstMatch.tap()
        app.buttons["close-row-parameter"].tap()
        closeTaskRow(app)
        XCTAssertTrue(description(app).waitForNonExistence(timeout: 10))
        app.tabBars.buttons["Upcoming"].tap()
        let upcomingRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "upcoming-planned-", "Keyboard task")).firstMatch
        XCTAssertTrue(upcomingRow.waitForExistence(timeout: 10))
        try commands.perform("select") { app.typeKey(XCUIKeyboardKey.downArrow, modifierFlags: .command) }
        XCTAssertTrue(app.buttons["edit-task"].waitForExistence(timeout: 5))
        capture("iPad selected task with simultaneous tabs list and detail", app: app)
        try commands.perform("edit") { app.typeKey("e", modifierFlags: .command) }
        XCTAssertTrue(description(app).waitForExistence(timeout: 5))
        replaceTaskText(description(app), with: "Keyboard task revised", app: app)
        capture("iPad in-list editor after keyboard command", app: app)
        let editedField = description(app)
        try commands.perform("saveEdit") { app.typeKey(XCUIKeyboardKey.return, modifierFlags: .command) }
        XCTAssertTrue(editedField.waitForNonExistence(timeout: 10))
        let revisedUpcomingRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "upcoming-planned-", "Keyboard task revised")).firstMatch
        XCTAssertTrue(revisedUpcomingRow.waitForExistence(timeout: 10))
        try commands.perform("complete") { app.typeKey(XCUIKeyboardKey.return, modifierFlags: [.command, .shift]) }
        XCTAssertTrue(app.buttons["complete-task"].waitForNonExistence(timeout: 10))
        try commands.perform("completedView") { app.typeKey("4", modifierFlags: .command) }
        XCTAssertTrue(taskRow(named: "Keyboard task revised", app: app).waitForExistence(timeout: 10))
        capture("iPad completed view from injected command", app: app)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Done"].waitForExistence(timeout: 10))
        selectDoneTasks(app)
        XCTAssertTrue(taskRow(named: "Keyboard task revised", app: app).waitForExistence(timeout: 10))
        openTaskInformation(taskRow(named: "Keyboard task revised", app: app), app: app)
        XCTAssertTrue(app.buttons["edit-task"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["complete-task"].exists)
        capture("iPad completed task after persistent reopen", app: app)
    }

    func testProjectTodayWaitingUpcomingAndPortraitKeepOneTask() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 10))
        app.buttons["New task"].tap()
        let field = description(app)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Adaptive planned task")
        let project = app.textFields["task-project"]
        focusTaskText(project, app: app)
        project.typeText("Workspace")
        tapTaskControlAtCenter(app.buttons["dismiss-editor-keyboard"], app: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        setDateSwitch("planned-day-enabled", to: true, app: app)
        setDateSwitch("deadline-enabled", to: true, app: app)
        setDateSwitch("waiting-date-enabled", to: true, app: app)
        app.buttons["save-task"].tap()
        app.tabBars.buttons["Projects"].tap()
        XCTAssertTrue(app.buttons["project-Workspace"].waitForExistence(timeout: 10))
        capture("iPad Projects list", app: app)
        app.buttons["project-Workspace"].tap()
        XCTAssertTrue(taskRow(named: "Adaptive planned task", app: app).waitForExistence(timeout: 10))
        capture("iPad project task list", app: app)
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(taskRow(named: "Adaptive planned task", app: app).waitForExistence(timeout: 10))
        openTaskInformation(taskRow(named: "Adaptive planned task", app: app), app: app)
        XCTAssertTrue(app.buttons["edit-task"].waitForExistence(timeout: 5))
        capture("iPad project Today waiting task and detail", app: app)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["edit-task"].waitForExistence(timeout: 5))
        capture("iPad portrait selected task", app: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        app.terminate()
        app.launchEnvironment["TSK_TEST_NOW"] = "1791972000"
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Upcoming"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Upcoming"].tap()
        let planned = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "upcoming-planned-")).firstMatch
        let deadline = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "upcoming-deadline-")).firstMatch
        XCTAssertTrue(planned.waitForExistence(timeout: 10))
        XCTAssertTrue(deadline.exists)
        XCTAssertEqual(planned.identifier.suffix(36), deadline.identifier.suffix(36))
        openTaskInformation(planned, app: app)
        XCTAssertTrue(app.buttons["edit-task"].waitForExistence(timeout: 5))
        capture("iPad Upcoming shared identity with detail", app: app)
    }

    func testCustomTabAndAccessibilityText() throws {
        let app = launch(arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(revealWorkspaceSetting("custom-views", app: app))
        XCTAssertEqual(app.buttons["custom-views"].label, "Views")
        XCTAssertFalse(app.otherElements["workspace-detail-empty"].exists, "Largest text must not reserve a third column for empty detail")
        app.buttons["custom-views"].tap()
        app.buttons["new-custom-view"].tap()
        let name = app.textFields["custom-view-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("All local tasks")
        tapTaskControlAtCenter(app.buttons["dismiss-filter-keyboard"], app: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        tapTaskControl(app.buttons["save-custom-view"], app: app)
        activateSavedWorkspaceView(app)
        XCTAssertTrue(app.staticTexts["No matching tasks"].waitForExistence(timeout: 10))
        capture("iPad custom tab at accessibility text size", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["workspace-accessibility-navigation"].firstMatch.exists)
        XCTAssertGreaterThan(app.tabBars.firstMatch.frame.midY, app.frame.midY)
        app.buttons["New task"].tap()
        let field = description(app)
        guard revealTaskElement(field, in: "task-editor-form", app: app) else { return }
        focusTaskText(field, app: app)
        field.typeText("Accessible task")
        if app.buttons["dismiss-editor-keyboard"].exists { tapTaskControlAtCenter(app.buttons["dismiss-editor-keyboard"], app: app) }
        tapTaskControl(app.buttons["save-task"], app: app)
        let row = taskRow(named: "Accessible task", app: app)
        guard waitForTaskSave(app, row: row, timeout: 15) else { return }
        let identity = row.identifier
        openTaskInformation(row, app: app)
        XCTAssertTrue(app.buttons["edit-task"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["task-detail-description"].label, "Accessible task")
        capture("iPad largest text opens the same task in sequential detail", app: app)
        tapTaskControl(app.buttons["edit-task"], app: app)
        let editedField = description(app)
        guard revealTaskElement(editedField, in: "task-editor-form", app: app) else { return }
        replaceTaskText(editedField, with: "Accessible task revised", app: app)
        if app.buttons["dismiss-editor-keyboard"].exists { tapTaskControlAtCenter(app.buttons["dismiss-editor-keyboard"], app: app) }
        tapTaskControl(app.buttons["save-task"], app: app)
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !app.collectionViews["task-editor-form"].exists && app.staticTexts["task-detail-description"].exists && app.staticTexts["task-detail-description"].label == "Accessible task revised"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 15), .completed)
        tapTaskControl(app.navigationBars["Task"].buttons.element(boundBy: 0), app: app)
        let revised = taskRow(named: "Accessible task revised", app: app)
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in revised.exists && revised.isHittable && !app.buttons["edit-task"].exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 10), .completed)
        XCTAssertEqual(revised.identifier, identity)
        XCTAssertTrue(app.tabBars.buttons["All local tasks"].isSelected)
        capture("iPad largest text returns to the same task and custom view", app: app)
    }

    private func launch(arguments: [String] = []) -> XCUIApplication {
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_NOW"] = "1792144800"
        app.launchArguments = arguments + ["-AppleLocale", "en_US", "-AppleLanguages", "(en)"]
        app.launch()
        return app
    }

    private func description(_ app: XCUIApplication) -> XCUIElement {
        app.textFields["task-description"].firstMatch
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
