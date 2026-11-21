import UIKit
import XCTest

@MainActor final class CalendarPresentationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        XCUIDevice.shared.appearance = .light
    }

    override func tearDownWithError() throws {
        XCUIApplication().terminate()
        XCUIDevice.shared.orientation = .portrait
        XCUIDevice.shared.appearance = .light
    }

    func testPopulatedCalendarShowsEventsAboveTasksAcrossAppearances() throws {
        for (appearance, largeText) in [("light", false), ("dark", false), ("light", true)] {
            XCUIDevice.shared.appearance = appearance == "dark" ? .dark : .light
            let app = try launch("populated", largeText: largeText)
            let timed = event("Design review with the product team", app)
            XCTAssertTrue(timed.waitForExistence(timeout: 10))
            XCTAssertTrue(dayOverview(app).exists)
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
            XCTAssertGreaterThanOrEqual(task.frame.minY, spanning.frame.maxY)
            XCTAssertGreaterThanOrEqual(task.frame.minY, timed.frame.maxY)
            capture("Tasks below the Calendar strip \(appearance)\(largeText ? " accessibility XXXL" : "")", app)
            openTaskInformation(task, app: app)
            XCTAssertTrue(app.staticTexts["task-detail-description"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.staticTexts["task-detail-description"].label, "Prepare the release")
            capture("Task detail regression \(appearance)\(largeText ? " accessibility XXXL" : "")", app)
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
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Completed"), object: app.staticTexts["task-detail-status"])
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 10), .completed)
    }

    func testDisplayedDayCalendarReadsEventsWithoutChangingTasks() throws {
        let replica = UUID().uuidString
        let app = try launch("populated", replica: replica)
        let timed = event("Design review with the product team", app)
        XCTAssertTrue(timed.waitForExistence(timeout: 10))
        let task = taskRow(named: "Prepare the release", app: app)
        XCTAssertTrue(task.isHittable)
        XCTAssertEqual(dayOverview(app).value as? String, "8:00–18:00")
        for title in ["Team offsite", "Overnight support", "Design review with the product team", "Untitled event"] {
            let displayed = event(title, app)
            XCTAssertTrue(displayed.exists)
            XCTAssertLessThanOrEqual(displayed.frame.maxY, task.frame.minY)
        }
        capture("Calendar strip above the task list", app)
        let originalEventID = timed.identifier
        browseDay(1, app: app)
        let nextDayEvent = event("Design review with the product team", app)
        let refreshed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in nextDayEvent.exists && nextDayEvent.identifier != originalEventID }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [refreshed], timeout: 10), .completed)
        XCTAssertFalse(taskRow(named: "Prepare the release", app: app).exists)
        XCTAssertTrue(event("Untitled event", app).exists)
        XCTAssertTrue(dayOverview(app).exists)
        capture("Displayed next day reads its Calendar events", app)
        browseDay(-1, app: app)
        XCTAssertTrue(taskRow(named: "Prepare the release", app: app).waitForExistence(timeout: 10))
        XCTAssertTrue(taskRow(named: "Prepare the release", app: app).isHittable)
        capture("Returning to Today retains task dates and events", app)
        app.terminate()
        let reopened = try launch("populated", replica: replica)
        XCTAssertTrue(taskRow(named: "Prepare the release", app: reopened).waitForExistence(timeout: 10))
        XCTAssertTrue(event("Team offsite", reopened).exists)
        openCalendarSettings(reopened)
        let start = reopened.steppers["calendar-start-hour"]
        let end = reopened.steppers["calendar-end-hour"]
        XCTAssertEqual(start.value as? String, "08:00")
        XCTAssertEqual(end.value as? String, "18:00")
        XCTAssertTrue(reopened.switches["calendar-visibility-presentation"].exists)
        capture("Calendar settings with restored hour controls", reopened)
        for _ in 0..<3 { tapTaskControl(start.buttons["calendar-start-hour-Increment"], app: reopened) }
        XCTAssertEqual(start.value as? String, "11:00")
        reopened.terminate()

        let configured = try launch("populated", replica: replica)
        let overview = dayOverview(configured)
        XCTAssertTrue(overview.waitForExistence(timeout: 10))
        XCTAssertEqual(overview.value as? String, "11:00–18:00")
        let outsideHours = event("Design review with the product team", configured)
        XCTAssertTrue(outsideHours.exists)
        XCTAssertLessThanOrEqual(overview.frame.maxY, outsideHours.frame.minY)
        XCTAssertLessThanOrEqual(outsideHours.frame.maxY, taskRow(named: "Prepare the release", app: configured).frame.minY)
        capture("Saved hours keep out-of-hours events above tasks", configured)
    }

    func testCalendarVisibilityTogglesFilterIndependentlyAndPersistAcrossLaunches() throws {
        let replica = UUID().uuidString
        let app = try launch("populated", replica: replica)
        XCTAssertTrue(event("Team offsite", app).waitForExistence(timeout: 10))
        capture("Visibility before hiding calendars", app)
        openCalendarSettings(app)
        let work = app.switches["calendar-visibility-presentation"]
        let personal = app.switches["calendar-visibility-personal"]
        let empty = app.switches["calendar-visibility-empty"]
        XCTAssertTrue(work.waitForExistence(timeout: 10))
        XCTAssertEqual(work.value as? String, "1")
        XCTAssertEqual(personal.value as? String, "1")
        XCTAssertEqual(empty.value as? String, "1")
        capture("Visibility Settings all calendars including empty calendar", app)
        setCalendarVisibility("calendar-visibility-presentation", visible: false, app: app)
        XCTAssertEqual(work.value as? String, "0")
        closeCalendarSettings(app)
        XCTAssertTrue(event("Team offsite", app).waitForNonExistence(timeout: 10))
        XCTAssertFalse(event("Design review with the product team", app).exists)
        XCTAssertFalse(event("Overnight support", app).exists)
        XCTAssertTrue(event("Untitled event", app).exists)
        XCTAssertTrue(taskRow(named: "Prepare the release", app: app).exists)
        capture("Visibility one calendar hidden leaves other calendar and tasks", app)
        let originalPersonalID = event("Untitled event", app).identifier
        browseDay(1, app: app)
        let personalNextDay = event("Untitled event", app)
        let nextDayRead = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in personalNextDay.exists && personalNextDay.identifier != originalPersonalID }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [nextDayRead], timeout: 10), .completed)
        XCTAssertFalse(event("Team offsite", app).exists)
        XCTAssertFalse(event("Design review with the product team", app).exists)
        capture("Displayed next day retains calendar visibility", app)
        app.terminate()

        let reopened = try launch("populated", replica: replica)
        XCTAssertTrue(event("Untitled event", reopened).waitForExistence(timeout: 10))
        XCTAssertFalse(event("Team offsite", reopened).exists)
        openCalendarSettings(reopened)
        XCTAssertEqual(reopened.switches["calendar-visibility-presentation"].value as? String, "0")
        setCalendarVisibility("calendar-visibility-personal", visible: false, app: reopened)
        closeCalendarSettings(reopened)
        assertCalendarHidden(reopened)
        XCTAssertTrue(taskRow(named: "Prepare the release", app: reopened).isHittable)
        capture("Visibility all event calendars hidden leaves tasks usable", reopened)
        openCalendarSettings(reopened)
        setCalendarVisibility("calendar-visibility-presentation", visible: true, app: reopened)
        closeCalendarSettings(reopened)
        XCTAssertTrue(event("Team offsite", reopened).waitForExistence(timeout: 10))
        XCTAssertFalse(event("Untitled event", reopened).exists)
        capture("Visibility re-enabled calendar restores its events", reopened)
        reopened.terminate()

        let accessible = try launch("populated", largeText: true, replica: replica)
        openCalendarSettings(accessible)
        let accessibleWork = accessible.switches["calendar-visibility-presentation"]
        XCTAssertTrue(revealTaskElement(accessibleWork, in: "calendar-display-settings-form", app: accessible, requireFullVisibility: true))
        XCTAssertEqual(accessibleWork.value as? String, "1")
        capture("Visibility Settings accessibility XXXL", accessible)
        setCalendarVisibility("calendar-visibility-presentation", visible: false, app: accessible)
        XCTAssertEqual(accessibleWork.value as? String, "0")
    }

    private func browseDay(_ offset: Int, app: XCUIApplication) {
        let pill = app.buttons["planner-date-pill"]
        let day = Date(timeIntervalSince1970: Double(pill.value as! String)!)
        let destination = Calendar.current.date(byAdding: .day, value: offset, to: day)!
        pill.tap()
        let date = app.buttons["planner-date-\(Int(destination.timeIntervalSince1970))"]
        XCTAssertTrue(date.waitForExistence(timeout: 5))
        date.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", String(Int(destination.timeIntervalSince1970))), object: pill)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
    }

    private func assertCalendarHidden(_ app: XCUIApplication) {
        assertTodayTaskList(app)
        XCTAssertFalse(dayOverview(app).exists)
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
        openWorkspaceView("Today", app: app)
        return app
    }

    private func event(_ title: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "calendar-event-", title)).firstMatch
    }

    private func dayOverview(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "calendar-day-overview").firstMatch
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Calendar presentation \(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor extension XCTestCase {
    func setCalendarVisibility(_ identifier: String, visible: Bool, app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let row = app.switches[identifier].firstMatch
        guard revealTaskElement(row, in: "calendar-display-settings-form", app: app, requireFullVisibility: true, file: file, line: line) else { return }
        let control = row.switches.firstMatch.exists ? row.switches.firstMatch : row
        guard control.isEnabled, control.isHittable else {
            XCTFail("Calendar switch is not ready: \(identifier)", file: file, line: line)
            return
        }
        recordTaskSwitchInteraction(row: row, selected: control, phase: "before", app: app)
        // The native switch's press recognizer can reject XCUITest's shortest taps.
        control.press(forDuration: 0.15)
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", visible ? "1" : "0"), object: row)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, file: file, line: line)
        recordTaskSwitchInteraction(row: row, selected: control, phase: "after", app: app)
    }
}
