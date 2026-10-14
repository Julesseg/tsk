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
        XCTAssertTrue(app.buttons["sidebar-view-unfinished"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.otherElements["workspace-detail-empty"].exists || app.staticTexts["Select a task"].exists)
        capture("iPad landscape empty workspace", app: app)
        app.typeKey("n", modifierFlags: .command)
        let field = description(app)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Keyboard task")
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: .command)
        XCTAssertTrue(field.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Keyboard task"].waitForExistence(timeout: 10))
        app.typeKey(XCUIKeyboardKey.downArrow, modifierFlags: .command)
        XCTAssertTrue(app.buttons["edit-task"].waitForExistence(timeout: 5))
        capture("iPad selected task with simultaneous sidebar list and detail", app: app)
        app.typeKey("e", modifierFlags: .command)
        XCTAssertTrue(description(app).waitForExistence(timeout: 5))
        description(app).typeText(" revised")
        capture("iPad native editor sheet", app: app)
        let editedField = description(app)
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: .command)
        XCTAssertTrue(editedField.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Keyboard task revised"].firstMatch.waitForExistence(timeout: 10))
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [.command, .shift])
        XCTAssertTrue(app.buttons["complete-task"].waitForNonExistence(timeout: 10))
        app.typeKey("4", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Keyboard task revised"].firstMatch.waitForExistence(timeout: 10))
        capture("iPad completed view from injected command", app: app)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["sidebar-view-completed"].waitForExistence(timeout: 10))
        app.buttons["sidebar-view-completed"].tap()
        XCTAssertTrue(app.staticTexts["Keyboard task revised"].firstMatch.waitForExistence(timeout: 10))
        app.staticTexts["Keyboard task revised"].firstMatch.tap()
        XCTAssertTrue(app.buttons["edit-task"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["complete-task"].exists)
        capture("iPad completed task after persistent reopen", app: app)
    }

    func testProjectTodayWaitingUpcomingAndPortraitKeepOneTask() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 10))
        app.buttons["new-task"].tap()
        let field = description(app)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Adaptive planned task")
        let project = app.textFields["task-project"]
        project.tap()
        project.typeText("Workspace")
        setDateSwitch("planned-day-enabled", to: true, app: app)
        setDateSwitch("deadline-enabled", to: true, app: app)
        setDateSwitch("waiting-date-enabled", to: true, app: app)
        app.buttons["save-task"].tap()
        XCTAssertTrue(app.buttons["sidebar-project-Workspace"].waitForExistence(timeout: 10))
        app.buttons["sidebar-project-Workspace"].tap()
        app.buttons["sidebar-view-today"].tap()
        XCTAssertTrue(app.staticTexts["Adaptive planned task"].firstMatch.waitForExistence(timeout: 10))
        app.staticTexts["Adaptive planned task"].firstMatch.tap()
        XCTAssertTrue(app.buttons["edit-task"].waitForExistence(timeout: 5))
        capture("iPad project Today waiting task and detail", app: app)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["edit-task"].waitForExistence(timeout: 5))
        capture("iPad portrait selected task", app: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        app.terminate()
        app.launchEnvironment["TSK_TEST_NOW"] = "1791972000"
        app.launch()
        XCTAssertTrue(app.buttons["sidebar-view-upcoming"].waitForExistence(timeout: 10))
        app.buttons["sidebar-view-upcoming"].tap()
        let planned = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "upcoming-planned-")).firstMatch
        let deadline = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "upcoming-deadline-")).firstMatch
        XCTAssertTrue(planned.waitForExistence(timeout: 10))
        XCTAssertTrue(deadline.exists)
        XCTAssertEqual(planned.identifier.suffix(36), deadline.identifier.suffix(36))
        planned.tap()
        XCTAssertTrue(app.buttons["edit-task"].waitForExistence(timeout: 5))
        capture("iPad Upcoming shared identity with detail", app: app)
    }

    func testNativeSidebarCustomViewAndAccessibilityText() throws {
        let app = launch(arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(revealTaskElement(app.buttons["custom-views"], in: "workspace-sidebar", app: app))
        app.buttons["custom-views"].tap()
        app.buttons["new-custom-view"].tap()
        let name = app.textFields["custom-view-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("All local tasks")
        app.buttons["save-custom-view"].tap()
        XCTAssertTrue(revealTaskElement(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "sidebar-custom-")).firstMatch, in: "workspace-sidebar", app: app))
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "sidebar-custom-")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["No matching tasks"].waitForExistence(timeout: 10))
        capture("iPad native custom view sidebar at accessibility text size", app: app)
    }

    private func launch(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_NOW"] = "1792144800"
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func description(_ app: XCUIApplication) -> XCUIElement {
        app.textFields["task-description"].exists ? app.textFields["task-description"] : app.textViews["task-description"]
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
