import XCTest

@MainActor final class CalendarTodayUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testRealCalendarTodayReadOnlyClippingStoreChangeForegroundAndRevocation() throws {
        XCTAssertEqual(ProcessInfo.processInfo.environment["TSK_UI_ISOLATED_SIMULATOR"], "1")
        let token = UUID().uuidString
        let app = configuredApp(token)
        app.resetAuthorizationStatus(for: .calendar)
        app.launchEnvironment["TSK_TEST_CALENDAR_FIXTURE"] = token
        addTeardownBlock {
            app.terminate()
            app.launchEnvironment.removeValue(forKey: "TSK_TEST_CALENDAR_FIXTURE")
            app.launchEnvironment["TSK_TEST_CALENDAR_CLEANUP"] = token
            app.launch()
            XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20))
            app.terminate(); app.resetAuthorizationStatus(for: .calendar)
        }
        app.launch(); select(.today, app)
        assertCalendarHidden(app)
        openCalendarSettings(app)
        app.buttons["calendar-request-access"].tap(); permission(allow: true)
        XCTAssertTrue(app.buttons["calendar-request-access"].waitForNonExistence(timeout: 20))
        closeCalendarSettings(app)
        let timed = event("Calendar fixture timed", app)
        XCTAssertTrue(revealTaskElement(timed, in: "task-list", app: app), app.staticTexts["calendar-fixture-error"].label)
        XCTAssertTrue(event("Calendar fixture all day", app).exists)
        XCTAssertTrue(event("Calendar fixture spanning", app).exists)
        XCTAssertFalse(event("Calendar fixture spanning", app).label.contains("Continues from an earlier day"))
        XCTAssertFalse(event("Calendar fixture spanning", app).label.contains("Continues into a later day"))
        XCTAssertFalse(event("Calendar fixture tomorrow excluded", app).exists)
        XCTAssertFalse(event("Calendar fixture boundary excluded", app).exists)
        XCTAssertTrue(app.staticTexts["calendar-fixture-verified"].exists)
        capture("Actual local Calendar events clipped to Today; source readback unchanged", app)
        XCTAssertTrue(revealTaskElement(app.buttons["calendar-fixture-add"], in: "task-list", app: app))
        app.buttons["calendar-fixture-add"].tap()
        XCTAssertTrue(event("Calendar fixture observed change", app).waitForExistence(timeout: 20), "Actual EKEventStoreChanged must refresh Today")
        capture("Actual EventKit change notification refresh", app)
        select(.unfinished, app)
        XCTAssertFalse(event("Calendar fixture timed", app).exists)
        app.terminate(); app.launch(); select(.today, app)
        XCTAssertTrue(event("Calendar fixture observed change", app).waitForExistence(timeout: 20))
        capture("Foreground Calendar refetch", app)
        app.terminate(); app.resetAuthorizationStatus(for: .calendar)
        app.launchEnvironment.removeValue(forKey: "TSK_TEST_CALENDAR_FIXTURE")
        app.launch(); select(.today, app)
        assertCalendarHidden(app)
        XCTAssertFalse(event("Calendar fixture timed", app).exists)
        openCalendarSettings(app)
        app.buttons["calendar-request-access"].tap(); permission(allow: false)
        XCTAssertTrue(app.buttons["calendar-request-access"].waitForExistence(timeout: 10))
        capture("Actual Calendar denial managed in Settings", app)
        closeCalendarSettings(app)
        assertCalendarHidden(app)
        capture("Actual Calendar permission revoked and denied with no Calendar area", app)
        openCalendarSettings(app)
        app.buttons["calendar-request-access"].tap()
        XCTAssertTrue(XCUIApplication(bundleIdentifier: "com.apple.Preferences").wait(for: .runningForeground, timeout: 10))
        app.activate()
        XCTAssertTrue(app.buttons["calendar-request-access"].waitForExistence(timeout: 10))
        closeCalendarSettings(app)
        assertCalendarHidden(app)
        createTask("Task after Calendar denial", app)
        XCTAssertTrue(taskRow(named: "Task after Calendar denial", app: app).waitForExistence(timeout: 15))
        app.terminate(); app.resetAuthorizationStatus(for: .calendar)
        app.launchEnvironment.removeValue(forKey: "TSK_TEST_CALENDAR_CLEANUP")
        app.launch(); select(.today, app)
        assertCalendarHidden(app)
        openCalendarSettings(app)
        app.buttons["calendar-request-access"].tap(); permission(allow: true)
        XCTAssertTrue(app.buttons["calendar-request-access"].waitForNonExistence(timeout: 20))
        closeCalendarSettings(app)
        select(.unfinished, app)
    }

    func testInjectedCalendarReadFailureKeepsTaskCaptureAndCompletionUsable() {
        let app = configuredApp(UUID().uuidString)
        app.launchEnvironment["TSK_TEST_CALENDAR_READ_FAILURE"] = "1"
        app.resetAuthorizationStatus(for: .calendar)
        defer { app.terminate(); app.resetAuthorizationStatus(for: .calendar) }
        app.launch(); select(.today, app)
        assertCalendarHidden(app)
        openCalendarSettings(app)
        app.buttons["calendar-request-access"].tap(); permission(allow: true)
        XCTAssertTrue(app.buttons["calendar-request-access"].waitForNonExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["calendar-read-error"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["calendar-read-error"].label, "Calendar unavailable")
        XCTAssertEqual(app.buttons["calendar-refresh"].label, "Retry")
        capture("Injected protocol read failure is managed in Settings", app)
        closeCalendarSettings(app)
        assertCalendarHidden(app)
        capture("Injected protocol read failure hides Calendar; ordinary task controls remain available", app)
        createTask("Calendar failure task", app)
        let row = taskRow(named: "Calendar failure task", app: app)
        XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
        XCTAssertTrue(app.buttons["complete-task"].waitForExistence(timeout: 10))
        app.buttons["complete-task"].tap()
    }

    private func assertCalendarHidden(_ app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["Tasks · Today"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["calendar-request-access"].exists)
        XCTAssertFalse(app.buttons["calendar-refresh"].exists)
        XCTAssertFalse(app.staticTexts["calendar-read-error"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'calendar-event-'")).firstMatch.exists)
    }

    private func openCalendarSettings(_ app: XCUIApplication) {
        tapTaskControl(app.buttons["workspace-settings"], app: app)
        let calendar = app.buttons["calendar-display-settings"]
        XCTAssertTrue(revealTaskElement(calendar, in: "workspace-settings-list", app: app, requireFullVisibility: true))
        tapTaskControl(calendar, app: app)
        XCTAssertTrue(app.buttons["calendar-request-access"].waitForExistence(timeout: 10))
    }

    private func closeCalendarSettings(_ app: XCUIApplication) {
        tapTaskControl(app.navigationBars["Calendar"].buttons.firstMatch, app: app)
        tapTaskControl(app.buttons["close-workspace-settings"], app: app)
    }

    private enum Selection { case today, unfinished }
    private func select(_ query: Selection, _ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20))
        let title = query == .today ? "Today" : "All"
        app.tabBars.buttons[title].tap()
    }
    private func configuredApp(_ token: String) -> XCUIApplication {
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = token
        app.launchEnvironment["TSK_TEST_NOW"] = "1792144800"
        app.launchEnvironment["TSK_UI_ISOLATED_SIMULATOR"] = "1"
        return app
    }
    private func event(_ title: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "calendar-event-", title)).firstMatch
    }
    private func createTask(_ title: String, _ app: XCUIApplication) {
        app.buttons["New task"].tap()
        let field = app.descendants(matching: .any).matching(identifier: "task-description").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap(); field.typeText(title)
        tapTaskControlAtCenter(app.buttons["dismiss-editor-keyboard"], app: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.collectionViews["task-editor-form"].exists, "Dismissing the keyboard must keep the editor open")
        XCTAssertEqual(field.value as? String, title)
        XCTAssertTrue(app.buttons["save-task"].exists)
        tapTaskControl(app.buttons["save-task"], app: app)
        XCTAssertTrue(waitForTaskSave(app, row: taskRow(named: title, app: app), timeout: 15))
    }
    private func permission(allow: Bool) {
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 15))
        let options = alert.buttons.allElementsBoundByIndex
        let button = options.first {
            let label = $0.label.lowercased()
            let denied = label.contains("don’t") || label.contains("don't") || label.contains("not allow")
            return label.contains("allow") && (allow ? !denied && !label.contains("add events only") : denied)
        }
        XCTAssertNotNil(button, "Actual Calendar permission choices: \(options.map(\.label))"); button?.tap()
    }
    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
