import UIKit
import XCTest

@MainActor
final class WorkspaceSettingsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
        XCUIDevice.shared.appearance = .light
    }

    func testCreationPlacementAndEverySettingsDestination() {
        let app = launch()
        capture("After empty workspace")
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
        capture("After task editor")
        let field = app.descendants(matching: .any).matching(identifier: "task-description").firstMatch
        focusTaskText(field, app: app)
        field.typeText("Plan the week")
        tapTaskControl(app.buttons["dismiss-editor-keyboard"], app: app)
        tapTaskControl(app.buttons["save-task"], app: app)
        XCTAssertTrue(waitForTaskSave(app, row: taskRow(named: "Plan the week", app: app), timeout: 15))
        capture("After populated workspace")
        tapTaskControl(settings, app: app)
        XCTAssertTrue(app.collectionViews["workspace-settings-list"].waitForExistence(timeout: 5))
        capture("After settings")
        XCTAssertFalse(app.buttons["task-shortcuts"].exists)
        XCTAssertFalse(app.buttons["spotlight-settings"].exists)
        XCTAssertFalse(app.buttons["spotlight-diagnostics"].exists)
        tapTaskControl(app.buttons["close-workspace-settings"], app: app)
        XCTAssertTrue(app.collectionViews["workspace-settings-list"].waitForNonExistence(timeout: 5))
        let destinations = [
            ("custom-views", "Views"),
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
        capture("After settings at largest text size")
        XCTAssertTrue(app.buttons["continuous-reminders-settings"].isHittable)
        XCTAssertTrue(revealWorkspaceSetting("custom-views", app: app, initialScrollUp: false))
        tapTaskControl(app.buttons["custom-views"], app: app)
        XCTAssertTrue(app.collectionViews["views-list"].waitForExistence(timeout: 5))
        capture("Views at largest text size")
        tapTaskControl(app.buttons["close-views"], app: app)
        tapTaskControl(app.buttons["workspace-settings"], app: app)
        tapTaskControl(app.buttons["close-workspace-settings"], app: app)
        XCTAssertTrue(app.collectionViews["workspace-settings-list"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["new-task"].isHittable)
    }

    func testViewsCapacityReorderingAndFirstTabPersistAcrossLaunch() {
        let app = launch()
        openWorkspaceSetting("custom-views", app: app)
        capture("Views with five default active tabs")
        tapTaskControl(app.buttons["new-custom-view"], app: app)
        let name = app.textFields["custom-view-name"]
        focusTaskText(name, app: app)
        name.typeText("All local tasks")
        tapTaskControl(app.buttons["dismiss-filter-keyboard"], app: app)
        tapTaskControl(app.buttons["save-custom-view"], app: app)
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "saved-view-")).firstMatch
        XCTAssertTrue(revealTaskElement(saved, in: "views-list", app: app))
        let id = String(saved.identifier.dropFirst("saved-view-".count))
        let add = app.buttons["activate-custom-" + id]
        XCTAssertFalse(add.isEnabled)
        capture("Views inactive custom filter at tab capacity")
        let remove = app.buttons["deactivate-completed"]
        XCTAssertTrue(revealTaskElement(remove, in: "views-list", app: app, initialScrollUp: false))
        tapTaskControl(remove, app: app)
        XCTAssertTrue(revealTaskElement(add, in: "views-list", app: app))
        XCTAssertTrue(add.isEnabled)
        tapTaskControl(add, app: app)
        XCTAssertTrue(revealTaskElement(saved, in: "views-list", app: app, initialScrollUp: false))
        let source = app.collectionViews["views-list"].cells.containing(.button, identifier: saved.identifier).firstMatch
        let first = app.collectionViews["views-list"].cells.containing(.button, identifier: "view-unfinished").firstMatch
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5))
            .press(forDuration: 1, thenDragTo: first.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.2)))
        capture("Views reordered custom tab first")
        tapTaskControl(app.buttons["close-views"], app: app)
        app.terminate()
        app.launch()
        let custom = app.tabBars.buttons["All local tasks"]
        XCTAssertTrue(custom.waitForExistence(timeout: 15))
        XCTAssertTrue(custom.isSelected)
        XCTAssertEqual(app.tabBars.buttons.element(boundBy: 0).label, "All local tasks")
        XCTAssertEqual(app.tabBars.buttons.count, 5)
        XCTAssertFalse(app.tabBars.buttons["Completed"].exists)
        capture("First active custom tab after relaunch")
        openWorkspaceSetting("custom-views", app: app)
        for identifier in ["unfinished", "today", "upcoming", "projects"] {
            let button = app.buttons["deactivate-" + identifier]
            XCTAssertTrue(revealTaskElement(button, in: "views-list", app: app, initialScrollUp: false))
            tapTaskControl(button, app: app)
        }
        XCTAssertFalse(app.buttons["deactivate-custom-" + id].isEnabled)
        capture("Views keeps one active tab")
        openSavedViewOptions(app)
        tapTaskMenuItem(app.buttons["Delete"], app: app)
        XCTAssertTrue(saved.waitForNonExistence(timeout: 5))
        tapTaskControl(app.buttons["close-views"], app: app)
        XCTAssertEqual(app.tabBars.buttons.count, 1)
        XCTAssertTrue(app.buttons["new-task"].isHittable)
    }

    func testProjectsNavigateToTasksAndSettingsUseNeutralColors() {
        let app = launch()
        tapTaskControl(app.buttons["new-task"], app: app)
        let description = app.descendants(matching: .any).matching(identifier: "task-description").firstMatch
        focusTaskText(description, app: app)
        description.typeText("Prepare launch")
        let project = app.textFields["task-project"]
        focusTaskText(project, app: app)
        project.typeText("Launch")
        tapTaskControl(app.buttons["dismiss-editor-keyboard"], app: app)
        tapTaskControl(app.buttons["save-task"], app: app)
        XCTAssertTrue(waitForTaskSave(app, row: taskRow(named: "Prepare launch", app: app), timeout: 15))
        tapTaskControl(app.tabBars.buttons["Projects"], app: app)
        XCTAssertTrue(app.buttons["project-Launch"].waitForExistence(timeout: 10))
        capture("Projects list")
        tapTaskControl(app.buttons["project-Launch"], app: app)
        XCTAssertTrue(taskRow(named: "Prepare launch", app: app).waitForExistence(timeout: 10))
        capture("Project tasks")
        tapTaskControl(taskRow(named: "Prepare launch", app: app), app: app)
        XCTAssertTrue(app.buttons["edit-task"].waitForExistence(timeout: 5))
        capture("Project task detail")
        tapTaskControl(app.navigationBars["Task"].buttons.element(boundBy: 0), app: app)
        tapTaskControl(app.navigationBars["Launch"].buttons.element(boundBy: 0), app: app)
        XCTAssertTrue(app.buttons["project-Launch"].waitForExistence(timeout: 5))
        XCUIDevice.shared.appearance = .dark
        capture("Projects dark")
        tapTaskControl(app.buttons["workspace-settings"], app: app)
        XCTAssertTrue(app.collectionViews["workspace-settings-list"].waitForExistence(timeout: 5))
        capture("Settings neutral dark")
        openWorkspaceSetting("custom-views", app: app)
        capture("Views dark")
        tapTaskControl(app.buttons["close-views"], app: app)
        XCUIDevice.shared.appearance = .light
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

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
