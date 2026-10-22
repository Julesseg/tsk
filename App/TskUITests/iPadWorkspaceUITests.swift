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

    func testCompactWindowKeepsUnfavoritedViewAndRegularPreference() throws {
        let app = launch()
        XCTAssertTrue(workspaceTab("Today", app: app).waitForExistence(timeout: 15))
        let initial = app.windows.firstMatch.frame
        let compactTarget = CGPoint(x: 500, y: initial.maxY - 100)
        let regularTarget = CGPoint(x: initial.maxX - 8, y: initial.maxY - 8)
        resizeWindow(app, toward: compactTarget)
        waitForCompactTabs(app)
        let compact = app.windows.firstMatch.frame
        XCTAssertLessThan(compact.width, initial.width / 2)
        XCTAssertEqual(app.tabBars.buttons.count, 4)
        XCTAssertTrue(workspaceTab("Today", app: app).isSelected)
        XCTAssertLessThan(app.buttons["New task"].frame.midY, compact.midY)
        XCTAssertTrue(app.buttons["workspace-views"].isHittable)
        capture("iPad compact empty Today native tabs", app: app)
        resizeWindow(app, toward: regularTarget)
        let regular = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let tab = self.workspaceTab("Today", app: app)
            return tab.exists && tab.frame.midY < app.windows.firstMatch.frame.midY && !app.tabBars.firstMatch.exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [regular], timeout: 10), .completed)
        tapTaskControl(app.buttons["workspace-views"], app: app)
        tapTaskMenuItem(app.buttons["manage-favorite-views"], app: app)
        tapTaskControl(app.buttons["new-custom-view"], app: app)
        let name = app.textFields["custom-view-name"]
        focusTaskText(name, app: app)
        name.typeText("Compact tasks")
        tapTaskControlAtCenter(app.buttons["dismiss-filter-keyboard"], app: app)
        tapTaskControl(app.buttons["save-custom-view"], app: app)
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "saved-view-")).firstMatch
        XCTAssertTrue(revealTaskElement(saved, in: "views-list", app: app))
        let id = String(saved.identifier.dropFirst("saved-view-".count))
        XCTAssertFalse(app.buttons["activate-custom-" + id].isEnabled)
        tapTaskControl(app.buttons["close-views"], app: app)
        tapTaskControl(app.buttons["workspace-views"], app: app)
        tapTaskMenuItem(app.collectionViews.buttons["Compact tasks"].firstMatch, app: app)
        XCTAssertEqual(app.staticTexts["workspace-title-text"].firstMatch.label, "Compact tasks")
        let sidebarToggle = app.buttons.matching(NSPredicate(format: "identifier IN %@", ["ToggleSideBar", "ToggleSidebar"])).firstMatch
        tapTaskControl(sidebarToggle, app: app)
        XCTAssertTrue(app.buttons["sidebar-settings"].waitForExistence(timeout: 5))
        resizeWindow(app, toward: compactTarget)
        waitForCompactTabs(app)
        XCTAssertEqual(app.staticTexts["workspace-title-text"].firstMatch.label, "Compact tasks")
        XCTAssertEqual(app.tabBars.buttons.count, 4)
        for title in ["Today", "Upcoming", "Projects", "All"] {
            XCTAssertFalse(workspaceTab(title, app: app).isSelected)
        }
        capture("iPad compact unfavorited custom view", app: app)
        tapTaskControl(app.buttons["workspace-views"], app: app)
        XCTAssertTrue(app.collectionViews.buttons["Compact tasks"].firstMatch.images["checkmark"].exists)
        capture("iPad compact Views retains selected custom view", app: app)
        tapTaskMenuItem(app.collectionViews.buttons["Compact tasks"].firstMatch, app: app)
        tapTaskControl(app.buttons["New task"], app: app)
        XCTAssertTrue(description(app).waitForExistence(timeout: 5))
        capture("iPad compact toolbar capture", app: app)
        tapTaskControl(app.buttons["Cancel"], app: app)
        XCTAssertEqual(app.staticTexts["workspace-title-text"].firstMatch.label, "Compact tasks")
        resizeWindow(app, toward: regularTarget)
        XCTAssertTrue(app.buttons["sidebar-settings"].waitForExistence(timeout: 10))
        XCTAssertGreaterThan(app.windows.firstMatch.frame.width, compact.width)
        XCTAssertEqual(app.staticTexts["workspace-title-text"].firstMatch.label, "Compact tasks")
        tapTaskControl(app.buttons["sidebar-settings"], app: app)
        XCTAssertTrue(app.collectionViews["workspace-settings-list"].waitForExistence(timeout: 5))
        tapTaskControl(app.buttons["close-workspace-settings"], app: app)
        capture("iPad live sidebar recovery after compact resizing", app: app)
        tapTaskControl(app.buttons["workspace-views"], app: app)
        tapTaskMenuItem(app.buttons["manage-favorite-views"], app: app)
        XCTAssertTrue(revealTaskElement(app.buttons["activate-custom-" + id], in: "views-list", app: app))
        XCTAssertFalse(app.buttons["activate-custom-" + id].isEnabled)
        tapTaskControl(app.buttons["close-views"], app: app)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["sidebar-settings"].waitForExistence(timeout: 15))
        capture("iPad regular preference retained after compact relaunch", app: app)
    }

    private func resizeWindow(_ app: XCUIApplication, toward target: CGPoint) {
        let window = app.windows.firstMatch.frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: window.maxX - 8, dy: window.maxY - 8))
            .press(forDuration: 0.3, thenDragTo: origin.withOffset(CGVector(dx: target.x, dy: target.y)), withVelocity: .slow, thenHoldForDuration: 1)
    }

    private func waitForCompactTabs(_ app: XCUIApplication) {
        let compact = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.tabBars.firstMatch.exists && app.tabBars.firstMatch.frame.midY > app.windows.firstMatch.frame.midY
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [compact], timeout: 10), .completed)
    }

    func testAdaptiveNavigationCatalogAndSidebarPreference() throws {
        let app = launch()
        let today = workspaceTab("Today", app: app)
        XCTAssertTrue(today.waitForExistence(timeout: 15))
        XCTAssertLessThan(today.frame.midY, app.frame.midY)
        XCTAssertFalse(app.tabBars.buttons["New task"].exists)
        XCTAssertLessThan(app.buttons["New task"].frame.midY, app.frame.midY)
        XCTAssertTrue(app.buttons["workspace-views"].isHittable)
        capture("iPad initial native top tabs", app: app)
        tapTaskControl(app.buttons["workspace-views"], app: app)
        tapTaskMenuItem(app.collectionViews.buttons["Done"].firstMatch, app: app)
        XCTAssertEqual(app.staticTexts["workspace-title-text"].firstMatch.label, "Done")
        XCTAssertFalse(workspaceTab("Today", app: app).isSelected)
        tapTaskControl(app.buttons["workspace-views"], app: app)
        XCTAssertTrue(app.collectionViews.buttons["Done"].firstMatch.images["checkmark"].exists)
        capture("iPad Views shows unfavorited current view", app: app)
        tapTaskMenuItem(app.collectionViews.buttons["Today"].firstMatch, app: app)
        tapTaskControl(app.buttons["New task"], app: app)
        let taskTitle = description(app)
        focusTaskText(taskTitle, app: app)
        taskTitle.typeText("Direct project task")
        let project = app.textFields["task-project"]
        focusTaskText(project, app: app)
        project.typeText("Workspace")
        tapTaskControlAtCenter(app.buttons["dismiss-editor-keyboard"], app: app)
        tapTaskControl(app.buttons["save-task"], app: app)
        XCTAssertTrue(waitForTaskSave(app, row: taskRow(named: "Direct project task", app: app), timeout: 15))
        tapTaskControl(app.buttons["workspace-views"], app: app)
        tapTaskMenuItem(app.buttons["manage-favorite-views"], app: app)
        tapTaskControl(app.buttons["new-custom-view"], app: app)
        let name = app.textFields["custom-view-name"]
        focusTaskText(name, app: app)
        name.typeText("Sidebar tasks")
        tapTaskControlAtCenter(app.buttons["dismiss-filter-keyboard"], app: app)
        tapTaskControl(app.buttons["save-custom-view"], app: app)
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "saved-view-")).firstMatch
        XCTAssertTrue(revealTaskElement(saved, in: "views-list", app: app))
        let id = String(saved.identifier.dropFirst("saved-view-".count))
        XCTAssertFalse(app.buttons["activate-custom-" + id].isEnabled)
        tapTaskControl(app.buttons["close-views"], app: app)
        let sidebar = app.buttons.matching(NSPredicate(format: "identifier IN %@", ["ToggleSideBar", "ToggleSidebar"])).firstMatch
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5), app.debugDescription)
        tapTaskControl(sidebar, app: app)
        XCTAssertTrue(app.buttons["sidebar-settings"].waitForExistence(timeout: 5))
        capture("iPad native sidebar complete catalog", app: app)
        let directProject = app.descendants(matching: .any).matching(identifier: "sidebar-project-Workspace").firstMatch
        XCTAssertTrue(directProject.waitForExistence(timeout: 5), app.debugDescription)
        tapTaskControl(directProject, app: app)
        XCTAssertTrue(taskRow(named: "Direct project task", app: app).waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["workspace-title-text"].firstMatch.label, "Workspace")
        capture("iPad sidebar direct project", app: app)
        let custom = app.descendants(matching: .any).matching(identifier: "sidebar-view-custom-" + id).firstMatch
        XCTAssertTrue(custom.waitForExistence(timeout: 5), app.debugDescription)
        tapTaskControl(custom, app: app)
        XCTAssertEqual(app.staticTexts["workspace-title-text"].firstMatch.label, "Sidebar tasks")
        let close = app.buttons.matching(NSPredicate(format: "identifier IN %@", ["ToggleSideBar", "ToggleSidebar"])).firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5), app.debugDescription)
        tapTaskControl(close, app: app)
        XCTAssertEqual(app.staticTexts["workspace-title-text"].firstMatch.label, "Sidebar tasks")
        for title in ["Today", "Upcoming", "Projects", "All"] {
            XCTAssertFalse(workspaceTab(title, app: app).isSelected)
        }
        capture("iPad unfavorited custom view after sidebar closes", app: app)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertEqual(app.staticTexts["workspace-title-text"].firstMatch.label, "Sidebar tasks")
        tapTaskControl(app.buttons["workspace-views"], app: app)
        XCTAssertTrue(app.collectionViews.buttons["Sidebar tasks"].firstMatch.images["checkmark"].exists)
        capture("iPad portrait unfavorited custom Views checkmark", app: app)
        tapTaskMenuItem(app.buttons["manage-favorite-views"], app: app)
        XCTAssertTrue(revealTaskElement(app.buttons["activate-custom-" + id], in: "views-list", app: app))
        XCTAssertFalse(app.buttons["activate-custom-" + id].isEnabled)
        capture("iPad unchanged favorites after browsing custom view", app: app)
        tapTaskControl(app.buttons["close-views"], app: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        tapTaskControl(sidebar, app: app)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["sidebar-settings"].waitForExistence(timeout: 15))
        capture("iPad sidebar preference restored", app: app)
        tapTaskControl(app.buttons["sidebar-settings"], app: app)
        XCTAssertTrue(app.collectionViews["workspace-settings-list"].waitForExistence(timeout: 5))
        tapTaskControl(app.buttons["close-workspace-settings"], app: app)
        let hideSidebar = app.buttons.matching(NSPredicate(format: "identifier IN %@", ["ToggleSideBar", "ToggleSidebar"])).firstMatch
        XCTAssertTrue(hideSidebar.waitForExistence(timeout: 5), app.debugDescription)
        tapTaskControl(hideSidebar, app: app)
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(today.waitForExistence(timeout: 15))
        XCTAssertLessThan(today.frame.midY, app.frame.midY)
    }

    func testInjectedKeyboardCaptureSelectionEditCompletionAndReopen() throws {
        let app = launch()
        selectDoneTasks(app)
        selectAllTasks(app)
        let commands = try TaskKeyboardCommand(.workspace, app: app)
        XCTAssertTrue(workspaceTab("All", app: app).waitForExistence(timeout: 10))
        XCTAssertTrue(app.otherElements["workspace-detail-empty"].exists || app.staticTexts["Select a task"].exists)
        capture("iPad landscape empty workspace", app: app)
        try commands.perform("capture") { app.typeKey("n", modifierFlags: .command) }
        let field = description(app)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Keyboard task")
        try commands.perform("saveNew") { app.typeKey(XCUIKeyboardKey.return, modifierFlags: .command) }
        XCTAssertTrue(field.waitForNonExistence(timeout: 10))
        XCTAssertTrue(taskRow(named: "Keyboard task", app: app).waitForExistence(timeout: 10))
        try commands.perform("select") { app.typeKey(XCUIKeyboardKey.downArrow, modifierFlags: .command) }
        XCTAssertTrue(app.buttons["edit-task"].waitForExistence(timeout: 5))
        capture("iPad selected task with simultaneous tabs list and detail", app: app)
        try commands.perform("edit") { app.typeKey("e", modifierFlags: .command) }
        XCTAssertTrue(description(app).waitForExistence(timeout: 5))
        description(app).typeText(" revised")
        capture("iPad native editor sheet", app: app)
        let editedField = description(app)
        try commands.perform("saveEdit") { app.typeKey(XCUIKeyboardKey.return, modifierFlags: .command) }
        XCTAssertTrue(editedField.waitForNonExistence(timeout: 10))
        XCTAssertTrue(taskRow(named: "Keyboard task revised", app: app).waitForExistence(timeout: 10))
        try commands.perform("complete") { app.typeKey(XCUIKeyboardKey.return, modifierFlags: [.command, .shift]) }
        XCTAssertTrue(app.buttons["complete-task"].waitForNonExistence(timeout: 10))
        try commands.perform("completedView") { app.typeKey("4", modifierFlags: .command) }
        XCTAssertTrue(taskRow(named: "Keyboard task revised", app: app).waitForExistence(timeout: 10))
        capture("iPad completed view from injected command", app: app)
        app.terminate()
        app.launch()
        XCTAssertTrue(workspaceTab("Done", app: app).waitForExistence(timeout: 10))
        selectDoneTasks(app)
        XCTAssertTrue(taskRow(named: "Keyboard task revised", app: app).waitForExistence(timeout: 10))
        taskRow(named: "Keyboard task revised", app: app).tap()
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
        workspaceTab("Projects", app: app).tap()
        XCTAssertTrue(app.buttons["project-Workspace"].waitForExistence(timeout: 10))
        capture("iPad Projects list", app: app)
        app.buttons["project-Workspace"].tap()
        XCTAssertTrue(taskRow(named: "Adaptive planned task", app: app).waitForExistence(timeout: 10))
        capture("iPad project task list", app: app)
        workspaceTab("Today", app: app).tap()
        XCTAssertTrue(taskRow(named: "Adaptive planned task", app: app).waitForExistence(timeout: 10))
        taskRow(named: "Adaptive planned task", app: app).tap()
        XCTAssertTrue(app.buttons["edit-task"].waitForExistence(timeout: 5))
        capture("iPad project Today waiting task and detail", app: app)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["edit-task"].waitForExistence(timeout: 5))
        capture("iPad portrait selected task", app: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        app.terminate()
        app.launchEnvironment["TSK_TEST_NOW"] = "1791972000"
        app.launch()
        XCTAssertTrue(workspaceTab("Upcoming", app: app).waitForExistence(timeout: 10))
        workspaceTab("Upcoming", app: app).tap()
        let planned = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "upcoming-planned-")).firstMatch
        let deadline = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "upcoming-deadline-")).firstMatch
        XCTAssertTrue(planned.waitForExistence(timeout: 10))
        XCTAssertTrue(deadline.exists)
        XCTAssertEqual(planned.identifier.suffix(36), deadline.identifier.suffix(36))
        planned.tap()
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
        XCTAssertLessThan(workspaceTab("All local tasks", app: app).frame.midY, app.frame.midY)
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
        tapTaskControl(row, app: app)
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
        XCTAssertTrue(workspaceTab("All local tasks", app: app).isSelected)
        capture("iPad largest text returns to the same task and custom view", app: app)
    }

    private func launch(arguments: [String] = []) -> XCUIApplication {
        let app = taskTestApplication()
        app.launchEnvironment["TSK_UI_ISOLATED_SIMULATOR"] = "1"
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_NOW"] = "1792144800"
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func description(_ app: XCUIApplication) -> XCUIElement {
        app.collectionViews["task-editor-form"].textFields["task-description"].firstMatch
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
