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
        XCTAssertFalse(app.staticTexts["task-sync-status"].exists)
        capture("After empty workspace")
        let create = app.buttons["New task"]
        let settings = app.buttons["workspace-settings"]
        XCTAssertEqual(app.buttons.matching(identifier: "workspace-settings").count, 1)
        XCTAssertGreaterThan(create.frame.midX, app.frame.midX)
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertLessThan(create.frame.midY, app.frame.minY + app.frame.height * 0.2)
            XCTAssertTrue(app.buttons["workspace-views"].isHittable)
            XCTAssertFalse(app.tabBars.buttons["New task"].exists)
        } else {
            XCTAssertGreaterThan(create.frame.midY, app.frame.maxY - app.frame.height * 0.2)
            let lastView = app.tabBars.buttons["All"]
            XCTAssertGreaterThan(create.frame.minX, lastView.frame.maxX)
            XCTAssertEqual(create.frame.midY, lastView.frame.midY, accuracy: 2)
        }
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
        tapTaskControlAtCenter(app.buttons["dismiss-editor-keyboard"], app: app)
        XCTAssertEqual(field.value as? String, "Plan the week")
        tapTaskControl(app.buttons["save-task"], app: app)
        XCTAssertTrue(waitForTaskSave(app, row: taskRow(named: "Plan the week", app: app), timeout: 15))
        XCTAssertFalse(app.staticTexts["task-sync-status"].exists)
        XCTAssertFalse(create.isSelected)
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
            if identifier == "custom-views" { capture("Views with four active tabs") }
            XCTAssertFalse(app.collectionViews["workspace-settings-list"].exists)
            tapTaskControl(app.navigationBars[title].buttons["Done"], app: app)
            XCTAssertTrue(app.buttons["workspace-settings"].waitForExistence(timeout: 5))
        }
        tapTaskControl(create, app: app)
        XCTAssertTrue(app.buttons["save-task"].waitForExistence(timeout: 5))
        tapTaskControl(app.buttons["Cancel"], app: app)
        XCTAssertTrue(taskRow(named: "Plan the week", app: app).waitForExistence(timeout: 5))
    }

    func testSettingsRemainReachableAtLargestTextSize() {
        let app = launch(arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(app.buttons["New task"].isHittable)
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
        XCTAssertTrue(app.buttons["New task"].isHittable)
    }

    func testViewsCapacityReorderingAndFirstTabPersistAcrossLaunch() {
        let app = launch(animationsEnabled: true)
        let hasCaptureTab = UIDevice.current.userInterfaceIdiom != .pad
        XCTAssertEqual(app.tabBars.buttons.allElementsBoundByIndex.map(\.label), ["Today", "Upcoming", "Projects", "All"] + (hasCaptureTab ? ["New task"] : []))
        XCTAssertTrue(app.tabBars.buttons["Today"].isSelected)
        openWorkspaceSetting("custom-views", app: app)
        capture("Views with four default active tabs")
        tapTaskControl(app.buttons["new-custom-view"], app: app)
        let name = app.textFields["custom-view-name"]
        focusTaskText(name, app: app)
        name.typeText("All local tasks")
        tapTaskControlAtCenter(app.buttons["dismiss-filter-keyboard"], app: app)
        XCTAssertEqual(name.value as? String, "All local tasks")
        tapTaskControl(app.buttons["save-custom-view"], app: app)
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "saved-view-")).firstMatch
        XCTAssertTrue(revealTaskElement(saved, in: "views-list", app: app))
        let id = String(saved.identifier.dropFirst("saved-view-".count))
        let add = app.buttons["activate-custom-" + id]
        XCTAssertFalse(add.isEnabled)
        capture("Views inactive custom filter at tab capacity")
        let remove = app.buttons["deactivate-unfinished"]
        XCTAssertTrue(revealTaskElement(remove, in: "views-list", app: app, initialScrollUp: false))
        tapTaskControl(remove, app: app)
        XCTAssertTrue(revealTaskElement(add, in: "views-list", app: app))
        XCTAssertTrue(add.isEnabled)
        tapTaskControl(add, app: app)
        XCTAssertTrue(revealTaskElement(saved, in: "views-list", app: app, initialScrollUp: false))
        let source = app.collectionViews["views-list"].cells.containing(.button, identifier: saved.identifier).firstMatch
        let first = app.collectionViews["views-list"].cells.containing(.button, identifier: "view-today").firstMatch
        let handle = source.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Reorder ")).firstMatch
        XCTAssertTrue(handle.exists)
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1,
                   thenDragTo: first.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.1)),
                   withVelocity: .slow, thenHoldForDuration: 1)
        let reordered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in source.frame.minY < first.frame.minY }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [reordered], timeout: 5), .completed)
        capture("Views reordered custom tab first")
        tapTaskControl(app.buttons["close-views"], app: app)
        app.terminate()
        app.launch()
        let custom = app.tabBars.buttons["All local tasks"]
        XCTAssertTrue(custom.waitForExistence(timeout: 15))
        XCTAssertTrue(custom.isSelected)
        XCTAssertEqual(app.tabBars.buttons.element(boundBy: 0).label, "All local tasks")
        XCTAssertEqual(app.tabBars.buttons.count, hasCaptureTab ? 5 : 4)
        XCTAssertFalse(app.tabBars.buttons["Done"].exists)
        capture("First active custom tab after relaunch")
        openWorkspaceSetting("custom-views", app: app)
        for identifier in ["today", "upcoming", "projects"] {
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
        XCTAssertEqual(app.tabBars.buttons.count, hasCaptureTab ? 2 : 1)
        XCTAssertTrue(app.buttons["New task"].isHittable)
    }

    func testProjectsNavigateToTasksAndSettingsUseNeutralColors() {
        let app = launch()
        tapTaskControl(app.buttons["New task"], app: app)
        let description = app.descendants(matching: .any).matching(identifier: "task-description").firstMatch
        focusTaskText(description, app: app)
        description.typeText("Prepare launch")
        let project = app.textFields["task-project"]
        focusTaskText(project, app: app)
        project.typeText("Launch")
        tapTaskControlAtCenter(app.buttons["dismiss-editor-keyboard"], app: app)
        tapTaskControl(app.buttons["save-task"], app: app)
        XCTAssertTrue(waitForTaskSave(app, row: taskRow(named: "Prepare launch", app: app), timeout: 15))
        tapTaskControl(app.tabBars.buttons["Projects"], app: app)
        XCTAssertTrue(app.buttons["project-Launch"].waitForExistence(timeout: 10))
        capture("Projects list")
        tapTaskControl(app.buttons["project-Launch"], app: app)
        XCTAssertTrue(taskRow(named: "Prepare launch", app: app).waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Launch"].waitForExistence(timeout: 5))
        capture("Project tasks")
        tapTaskControl(taskRow(named: "Prepare launch", app: app), app: app)
        XCTAssertTrue(app.buttons["edit-task"].waitForExistence(timeout: 5))
        capture("Project task detail")
        tapTaskControl(app.navigationBars["Task"].buttons.element(boundBy: 0), app: app)
        tapTaskControl(app.navigationBars["Launch"].buttons.element(boundBy: 0), app: app)
        XCTAssertTrue(app.buttons["project-Launch"].waitForExistence(timeout: 5))
        tapTaskControl(app.buttons["project-Launch"], app: app)
        XCTAssertTrue(app.navigationBars["Launch"].waitForExistence(timeout: 5))
        openWorkspaceSetting("custom-views", app: app)
        let projects = app.buttons["view-projects"]
        XCTAssertTrue(revealTaskElement(projects, in: "views-list", app: app))
        tapTaskControl(projects, app: app)
        XCTAssertTrue(app.collectionViews["projects-list"].waitForExistence(timeout: 5))
        tapTaskControl(app.buttons["project-Launch"], app: app)
        XCTAssertTrue(app.navigationBars["Launch"].waitForExistence(timeout: 5))
        openWorkspaceSetting("custom-views", app: app)
        tapTaskControl(app.buttons["new-custom-view"], app: app)
        let preview = app.buttons["apply-filter"]
        XCTAssertTrue(revealTaskElement(preview, in: "raw-filter-form", app: app))
        tapTaskControl(preview, app: app)
        XCTAssertTrue(app.navigationBars["Custom filter"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "workspace-settings").count, 1)
        capture("Unsaved filter preview")
        tapTaskControl(app.buttons["Close filter"], app: app)
        XCTAssertTrue(app.collectionViews["projects-list"].waitForExistence(timeout: 5))
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

    func testSynchronizationProgressStaysBesideWorkspaceTitle() throws {
        let ready = expectation(description: "Deferred synchronization server is listening")
        let server = try DeferredSynchronizationServer(ready: ready)
        defer { server.stop() }
        wait(for: [ready], timeout: 5)
        let port = try XCTUnwrap(server.port)
        let app = launch()
        func dismissPassword(_ deadline: TimeInterval) {
            for dialog in [app.alerts["Save Password?"], app.sheets["Save Password?"]] {
                guard ProcessInfo.processInfo.systemUptime < deadline else { return }
                if dialog.exists {
                    let notNow = dialog.buttons["Not Now"]
                    guard notNow.exists, notNow.isHittable else { return }
                    tapTaskControl(notNow, app: app, deadline: deadline)
                    return
                }
            }
        }
        openWorkspaceSetting("synchronization-settings", app: app)
        let fields = [
            (app.textFields["sync-server-url"], "http://127.0.0.1:\(port)"),
            (app.textFields["sync-client-id"], UUID().uuidString),
            (app.secureTextFields["sync-encryption-secret"], "isolated-progress-test")
        ]
        for (field, value) in fields {
            focusTaskText(field, app: app)
            field.typeText(value)
        }
        tapTaskControlAtCenter(app.buttons["dismiss-sync-keyboard"], app: app)
        tapTaskControl(app.buttons["save-sync-connection"], app: app)
        XCTAssertTrue(app.staticTexts["sync-connection-saved"].waitForExistence(timeout: 5))
        tapTaskControl(app.navigationBars["Synchronization"].buttons["Done"], app: app)
        for title in ["Today", "Projects"] {
            tapTaskControl(app.tabBars.buttons[title], app: app, beforeSample: dismissPassword)
            let progress = app.navigationBars.activityIndicators["workspace-sync-progress"].firstMatch
            XCTAssertTrue(progress.waitForExistence(timeout: 5))
            XCTAssertEqual(app.navigationBars.activityIndicators.matching(identifier: "workspace-sync-progress").count, 1)
            XCTAssertEqual(app.navigationBars.staticTexts.matching(identifier: "workspace-title-text").count, 1)
            let heading = try app.navigationBars.staticTexts["workspace-title-text"].snapshot()
            let progressFrame = try progress.snapshot().frame
            XCTAssertEqual(heading.label, title)
            XCTAssertGreaterThan(heading.frame.width, 0)
            XCTAssertGreaterThan(heading.frame.height, 0)
            XCTAssertTrue(app.frame.contains(heading.frame))
            XCTAssertGreaterThan(progressFrame.minX, heading.frame.maxX)
            XCTAssertEqual(progressFrame.midY, heading.frame.midY, accuracy: 12)
            XCTAssertFalse(app.staticTexts["task-sync-status"].exists)
            XCTAssertFalse(app.staticTexts["task-sync-error"].exists)
            XCTAssertFalse(app.buttons["retry-task-sync"].exists)
        }
        server.finish()
        XCTAssertTrue(app.activityIndicators["workspace-sync-progress"].waitForNonExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["task-sync-status"].exists)
        XCTAssertFalse(app.staticTexts["task-sync-error"].exists)
        openWorkspaceSetting("synchronization-settings", app: app, beforeSample: dismissPassword)
        XCTAssertTrue(app.staticTexts["sync-error"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["sync-now"].isEnabled)
    }

    private func launch(arguments: [String] = [], animationsEnabled: Bool = false) -> XCUIApplication {
        let app = taskTestApplication()
        app.launchEnvironment["TSK_UI_ISOLATED_SIMULATOR"] = "1"
        if animationsEnabled { app.launchEnvironment["TSK_UI_DISABLE_ANIMATIONS"] = "0" }
        app.launchArguments += arguments
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20))
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
