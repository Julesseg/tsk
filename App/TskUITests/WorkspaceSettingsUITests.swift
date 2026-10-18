import UIKit
import XCTest

@MainActor
final class WorkspaceSettingsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
    }

    override func tearDownWithError() throws { XCUIDevice.shared.orientation = .portrait }

    func testCreationPlacementAndEverySettingsDestination() {
        let app = launch()
        capture("After empty workspace", app)
        let create = app.buttons["new-task"]
        let settings = app.buttons["workspace-settings"]
        XCTAssertEqual(app.buttons.matching(identifier: "workspace-settings").count, 1)
        XCTAssertGreaterThan(create.frame.midX, app.frame.midX)
        XCTAssertGreaterThan(create.frame.midY, app.frame.maxY - app.frame.height * 0.2)
        XCTAssertGreaterThan(settings.frame.midX, app.frame.midX)
        XCTAssertLessThan(settings.frame.midY, app.frame.minY + app.frame.height * 0.2)
        XCTAssertFalse(app.buttons["workspace-more"].exists)
        XCTAssertFalse(app.buttons["custom-views"].exists)
        XCTAssertFalse(app.buttons["task-shortcuts"].exists)
        XCTAssertFalse(app.buttons["spotlight-settings"].exists)
        XCTAssertFalse(app.buttons["spotlight-pending"].exists)
        tapTaskControl(create, app: app)
        XCTAssertTrue(app.buttons["save-task"].waitForExistence(timeout: 5))
        capture("After task editor", app)
        let field = app.descendants(matching: .any).matching(identifier: "task-description").firstMatch
        focusTaskText(field, app: app)
        field.typeText("Plan the week")
        tapTaskControl(app.buttons["dismiss-editor-keyboard"], app: app)
        tapTaskControl(app.buttons["save-task"], app: app)
        XCTAssertTrue(waitForTaskSave(app, row: taskRow(named: "Plan the week", app: app), timeout: 15))
        capture("After populated workspace", app)
        tapTaskControl(settings, app: app)
        XCTAssertTrue(app.collectionViews["workspace-settings-list"].waitForExistence(timeout: 5))
        capture("After settings", app)
        XCTAssertFalse(app.buttons["task-shortcuts"].exists)
        XCTAssertFalse(app.buttons["spotlight-settings"].exists)
        XCTAssertFalse(app.buttons["spotlight-diagnostics"].exists)
        tapTaskControl(app.buttons["close-workspace-settings"], app: app)
        XCTAssertTrue(app.collectionViews["workspace-settings-list"].waitForNonExistence(timeout: 5))
        let destinations = [
            ("custom-views", "Custom views"),
            ("recurring-templates", "Recurring templates"),
            ("attribute-definitions", "Attribute definitions"),
            ("synchronization-settings", "Synchronization"),
            ("notification-settings", "Task notifications"),
            ("reminders-import", "Copy from Reminders"),
            ("continuous-reminders-settings", "Move from Reminders")
        ]
        for (identifier, title) in destinations {
            openWorkspaceSetting(identifier, app: app)
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10), identifier)
            XCTAssertFalse(app.collectionViews["workspace-settings-list"].exists)
            tapTaskControl(app.buttons["Done"], app: app)
            XCTAssertTrue(app.buttons["workspace-settings"].waitForExistence(timeout: 5))
        }
        tapTaskControl(create, app: app)
        XCTAssertTrue(app.buttons["save-task"].waitForExistence(timeout: 5))
        tapTaskControl(app.buttons["Cancel"], app: app)
        XCTAssertTrue(taskRow(named: "Plan the week", app: app).waitForExistence(timeout: 5))
    }

    func testSettingsRemainReachableAtLargestTextSize() {
        let app = launch(arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(app.buttons["new-task"].isHittable)
        XCTAssertTrue(revealWorkspaceSetting("continuous-reminders-settings", app: app))
        capture("After settings at largest text size", app)
        XCTAssertTrue(app.buttons["continuous-reminders-settings"].isHittable)
        XCTAssertTrue(revealWorkspaceSetting("custom-views", app: app))
        tapTaskControl(app.buttons["close-workspace-settings"], app: app)
        XCTAssertTrue(app.collectionViews["workspace-settings-list"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["new-task"].isHittable)
    }

    private func launch(arguments: [String] = []) -> XCUIApplication {
        let app = taskTestApplication()
        app.launchArguments += arguments
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["workspace-settings"].waitForExistence(timeout: 5))
        return app
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
