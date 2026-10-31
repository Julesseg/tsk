import UIKit
import XCTest

@MainActor final class CalendarPresentationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
        XCUIDevice.shared.appearance = .light
    }

    override func tearDownWithError() throws {
        XCUIApplication().terminate()
        XCUIDevice.shared.orientation = .portrait
        XCUIDevice.shared.appearance = .light
    }

    func testPopulatedCalendarOnlyShowsTimeAndTitleAboveTasksAcrossAppearances() throws {
        for (appearance, largeText) in [("light", false), ("dark", false), ("light", true)] {
            XCUIDevice.shared.appearance = appearance == "dark" ? .dark : .light
            let app = try launch("populated", largeText: largeText)
            let timed = event("Design review with the product team", app)
            XCTAssertTrue(timed.waitForExistence(timeout: 10))
            capture("Populated initial render", app)
            XCTAssertTrue(event("Team offsite", app).label.contains("All day"))
            XCTAssertTrue(event("Untitled event", app).exists)
            let spanning = event("Overnight support", app)
            XCTAssertFalse(spanning.label.contains("Continues"))
            XCTAssertFalse(timed.label.contains("Hidden calendar name"))
            XCTAssertFalse(timed.label.contains("Hidden event location"))
            XCTAssertFalse(app.staticTexts["Calendar · Today"].exists)
            XCTAssertFalse(app.staticTexts["Calendar events are read only. Calendar changes never change your tasks."].exists)
            capture("Populated \(appearance)\(largeText ? " accessibility XXXL" : "")", app)
            let task = taskRow(named: "Prepare the release", app: app)
            XCTAssertTrue(revealTaskElement(task, in: "task-list", app: app, requireFullVisibility: true))
            XCTAssertGreaterThan(task.frame.minY, spanning.frame.minY)
            capture("Tasks below Calendar \(appearance)\(largeText ? " accessibility XXXL" : "")", app)
            openTaskInformation(task, app: app)
            XCTAssertTrue(app.staticTexts["task-detail-description"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.staticTexts["task-detail-description"].label, "Prepare the release")
            capture("Task detail regression \(appearance)\(largeText ? " accessibility XXXL" : "")", app)
            app.terminate()
        }
    }

    func testEmptyCalendarDisappearsWithAndWithoutTasks() throws {
        for hasTask in [true, false] {
            let app = try launch("empty", hasTask: hasTask)
            assertTodayTaskList(app)
            XCTAssertFalse(app.staticTexts["calendar-empty"].exists)
            XCTAssertFalse(app.staticTexts["Calendar · Today"].exists)
            XCTAssertFalse(app.buttons["calendar-request-access"].exists)
            XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'calendar-event-'")).firstMatch.exists)
            if hasTask { XCTAssertTrue(taskRow(named: "Prepare the release", app: app).isHittable) }
            else { XCTAssertTrue(app.staticTexts["Nothing planned or due today"].exists) }
            capture("Empty Calendar \(hasTask ? "with task" : "empty tasks")", app)
            app.terminate()
        }
    }

    func testMissingAccessHidesCalendarAndEnablesFromSettings() throws {
        for state in ["notDetermined", "denied", "restricted", "writeOnly", "unavailable"] {
            let app = try launch(state)
            assertCalendarHidden(app)
            XCTAssertTrue(taskRow(named: "Prepare the release", app: app).isHittable)
            capture("Hidden Calendar access \(state)", app)
            openCalendarSettings(app)
            let enable = app.buttons["calendar-request-access"]
            XCTAssertTrue(enable.waitForExistence(timeout: 10))
            XCTAssertEqual(enable.label, "Enable Calendar")
            capture("Calendar access settings \(state)", app)
            if state == "notDetermined" || state == "writeOnly" || state == "unavailable" {
                tapTaskControl(enable, app: app)
                XCTAssertTrue(enable.waitForNonExistence(timeout: 10))
                closeCalendarSettings(app)
                XCTAssertTrue(event("Team offsite", app).waitForExistence(timeout: 10))
                capture("Enabled from \(state) Settings injected source", app)
            }
            app.terminate()
        }
    }

    func testReadFailureHidesCalendarAndSettingsRetryRecoversWithTasksUsable() throws {
        for largeText in [false, true] {
            let failed = try launch("failure", largeText: largeText)
            assertCalendarHidden(failed)
            XCTAssertTrue(taskRow(named: "Prepare the release", app: failed).isHittable)
            capture("Hidden Calendar read failure \(largeText ? "accessibility XXXL" : "light")", failed)
            openCalendarSettings(failed)
            let error = failed.staticTexts["calendar-read-error"]
            XCTAssertTrue(error.waitForExistence(timeout: 10))
            capture("Read failure Settings \(largeText ? "accessibility XXXL" : "light")", failed)
            tapTaskControl(failed.buttons["calendar-refresh"], app: failed)
            XCTAssertTrue(error.waitForNonExistence(timeout: 10))
            closeCalendarSettings(failed)
            XCTAssertTrue(event("Team offsite", failed).waitForExistence(timeout: 10))
            capture("Retry recovered from Settings \(largeText ? "accessibility XXXL" : "light")", failed)
            failed.terminate()
        }

        XCUIDevice.shared.appearance = .light
        let app = try launch("many")
        XCTAssertTrue(event("Team offsite", app).waitForExistence(timeout: 10))
        capture("Many events top", app)
        let last = event("Planning session 18", app)
        XCTAssertTrue(revealTaskElement(last, in: "task-list", app: app, initialScrollUp: true))
        let task = taskRow(named: "Prepare the release", app: app)
        XCTAssertTrue(revealTaskElement(task, in: "task-list", app: app, initialScrollUp: true))
        capture("Many events tasks remain reachable", app)
        openTaskInformation(task, app: app)
        XCTAssertTrue(revealTaskElement(app.buttons["complete-task"], in: "task-detail-form", app: app))
        tapTaskControl(app.buttons["complete-task"], app: app)
        XCTAssertTrue(task.waitForNonExistence(timeout: 10))
    }

    func testOverviewHoursSaveAcrossLaunchAndKeepEventsOutsideTheRange() throws {
        let replica = UUID().uuidString
        let app = try launch("populated", replica: replica)
        let overview = app.descendants(matching: .any).matching(identifier: "calendar-day-overview").firstMatch
        XCTAssertTrue(overview.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["full titles"].exists)
        XCTAssertFalse(app.staticTexts["Whole day"].exists)
        tapTaskControl(app.buttons["workspace-settings"], app: app)
        let settings = app.buttons["calendar-display-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        tapTaskControl(settings, app: app)
        let start = app.steppers["calendar-start-hour"]
        let end = app.steppers["calendar-end-hour"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        capture("Calendar settings default hours", app)
        for _ in 0..<2 { tapTaskControl(start.buttons["calendar-start-hour-Increment"], app: app) }
        for _ in 0..<7 { tapTaskControl(end.buttons["calendar-end-hour-Decrement"], app: app) }
        XCTAssertEqual(start.value as? String, "10:00")
        XCTAssertEqual(end.value as? String, "11:00")
        XCTAssertFalse(end.buttons["calendar-end-hour-Decrement"].isEnabled)
        capture("Calendar settings configured hours", app)
        app.terminate()
        let reopened = try launch("populated", replica: replica)
        let saved = reopened.descendants(matching: .any).matching(identifier: "calendar-day-overview").firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        XCTAssertEqual(saved.value as? String, "10:00–11:00")
        XCTAssertTrue(event("Untitled event", reopened).exists)
        XCTAssertTrue(event("Design review with the product team", reopened).exists)
        XCTAssertTrue(taskRow(named: "Prepare the release", app: reopened).isHittable)
        capture("Configured overview preserves outside-hour events after relaunch", reopened)
        reopened.terminate()
        let accessible = try launch("populated", largeText: true, replica: replica)
        tapTaskControl(accessible.buttons["workspace-settings"], app: accessible)
        let accessibleSettings = accessible.buttons["calendar-display-settings"]
        XCTAssertTrue(revealTaskElement(accessibleSettings, in: "workspace-settings-list", app: accessible, requireFullVisibility: true))
        tapTaskControl(accessibleSettings, app: accessible)
        XCTAssertEqual(accessible.steppers["calendar-start-hour"].value as? String, "10:00")
        XCTAssertEqual(accessible.steppers["calendar-end-hour"].value as? String, "11:00")
        capture("Calendar settings accessibility XXXL", accessible)
    }

    private func assertCalendarHidden(_ app: XCUIApplication) {
        assertTodayTaskList(app)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "calendar-day-overview").firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'calendar-event-'")).firstMatch.exists)
        XCTAssertFalse(app.buttons["calendar-request-access"].exists)
        XCTAssertFalse(app.buttons["calendar-refresh"].exists)
        XCTAssertFalse(app.staticTexts["calendar-read-error"].exists)
        XCTAssertFalse(app.staticTexts["Calendar · Today"].exists)
    }

    private func openCalendarSettings(_ app: XCUIApplication) {
        tapTaskControl(app.buttons["workspace-settings"], app: app)
        let calendar = app.buttons["calendar-display-settings"]
        XCTAssertTrue(revealTaskElement(calendar, in: "workspace-settings-list", app: app, requireFullVisibility: true))
        tapTaskControl(calendar, app: app)
        XCTAssertTrue(app.collectionViews["calendar-display-settings-form"].waitForExistence(timeout: 10))
    }

    private func closeCalendarSettings(_ app: XCUIApplication) {
        tapTaskControl(app.navigationBars["Calendar"].buttons.firstMatch, app: app)
        tapTaskControl(app.buttons["close-workspace-settings"], app: app)
    }

    private func launch(_ state: String, largeText: Bool = false, hasTask: Bool = true, replica: String = UUID().uuidString) throws -> XCUIApplication {
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = replica
        app.launchEnvironment["TSK_TEST_NOW"] = "1792144800"
        app.launchEnvironment["TSK_UI_ISOLATED_SIMULATOR"] = "1"
        app.launchEnvironment["TSK_TEST_CALENDAR_PRESENTATION"] = state
        if hasTask {
            let record: [String: Any] = ["id": replica, "attributes": [["key": "description", "value": "Prepare the release"], ["key": "status", "value": "pending"], ["key": "scheduled", "value": "1792108800"]]]
            app.launchEnvironment["TSK_TEST_RECORDED_RECURRENCE"] = String(decoding: try JSONSerialization.data(withJSONObject: [record]), as: UTF8.self)
        }
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Today"].tap()
        return app
    }

    private func event(_ title: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "calendar-event-", title)).firstMatch
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Calendar presentation \(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
