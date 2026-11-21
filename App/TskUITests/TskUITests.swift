import XCTest

@MainActor
final class TskUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testCaptureReviewCancelSaveAndRelaunch() async throws {
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_NOW"] = "1792144800"
        app.launchEnvironment["TSK_TEST_CALENDAR_PRESENTATION"] = "empty"
        let records = [
            ["id": "A1050000-0000-0000-0000-000000000001", "attributes": [["key": "description", "value": "Deadline orphan"], ["key": "status", "value": "pending"], ["key": "due", "value": "1792144800"]]],
            ["id": "A1050000-0000-0000-0000-000000000002", "attributes": [["key": "description", "value": "Project backlog"], ["key": "status", "value": "pending"], ["key": "project", "value": "Work"]]],
            ["id": "A1050000-0000-0000-0000-000000000003", "attributes": [["key": "description", "value": "Project scheduled"], ["key": "status", "value": "pending"], ["key": "project", "value": "Work"], ["key": "scheduled", "value": "1792144800"]]]
        ]
        app.launchEnvironment["TSK_TEST_RECORDED_RECURRENCE"] = String(decoding: try JSONSerialization.data(withJSONObject: records), as: UTF8.self)
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        XCTAssertFalse(app.buttons["workspace-views"].exists)
        XCTAssertTrue(app.buttons["open-inbox"].exists)
        XCTAssertTrue(app.buttons["open-projects"].exists)
        XCTAssertTrue(app.buttons["planner-date-pill"].exists)
        screenshot("Planner toolbar replaces primary tabs", app: app)
        app.buttons["New task"].tap()
        let description = app.descendants(matching: .any).matching(identifier: "task-description").firstMatch
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Cancel"].exists)
        let captureCell = app.cells.containing(.any, identifier: "task-description").firstMatch
        XCTAssertGreaterThanOrEqual(captureCell.frame.minY, app.navigationBars.firstMatch.frame.maxY, "The draft card must stay below the navigation header")
        XCTAssertEqual(app.staticTexts["workspace-title-text"].label, "Today")
        tapTaskControl(app.buttons["collapse-task-row"], app: app)
        XCTAssertTrue(description.waitForNonExistence(timeout: 5))
        let pill = app.buttons["planner-date-pill"]
        let today = try XCTUnwrap(pill.value as? String)
        XCTAssertLessThan(pill.frame.width, app.frame.width * 0.6)
        XCTAssertFalse(pill.frame.intersects(app.buttons["New task"].frame))
        expandPlannerCalendar(app)
        screenshot("Compact date pill morphs into its calendar", app: app)
        tapTaskControl(app.buttons["planner-date-" + today], app: app)
        XCTAssertTrue(app.otherElements["planner-month-calendar"].waitForNonExistence(timeout: 5))
        pill.swipeLeft()
        let changedDay = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != nil AND value != %@", today), object: pill)
        XCTAssertEqual(XCTWaiter.wait(for: [changedDay], timeout: 5), .completed)
        XCTAssertNotEqual(pill.value as? String, today)
        let capturedDay = Date(timeIntervalSince1970: try XCTUnwrap(Double(try XCTUnwrap(pill.value as? String))))
        let list = app.collectionViews["task-list"]
        let background = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: list.frame.midX, dy: list.frame.minY + min(300, list.frame.height / 2)))
        background.press(forDuration: 0.05, thenDragTo: background.withOffset(CGVector(dx: 220, dy: 0)), withVelocity: .slow, thenHoldForDuration: 0)
        assertPlannerDay(today, app: app)
        pill.swipeLeft()
        assertPlannerDay(String(Int(capturedDay.timeIntervalSince1970)), app: app)
        screenshot("Day paging from pill and background", app: app)
        let scheduledValue = capturedDay.formatted(date: .abbreviated, time: .omitted)
        app.buttons["New task"].tap()
        let reviewedDescription = app.descendants(matching: .any)["task-description"].firstMatch
        XCTAssertTrue(reviewedDescription.waitForExistence(timeout: 5))
        reviewedDescription.typeText("Buy milk from the market")
        tapTaskControlAtCenter(app.buttons["dismiss-row-keyboard"], app: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(captureCell.frame.minY, app.navigationBars.firstMatch.frame.maxY, "Hiding the keyboard must keep the draft below the navigation header")
        tapTaskControl(app.buttons["New task"], app: app)
        XCTAssertEqual(reviewedDescription.value as? String, "Buy milk from the market")
        XCTAssertEqual(app.buttons["row-project"].value as? String, "Not set")
        XCTAssertEqual(app.buttons["row-scheduled"].value as? String, scheduledValue)
        openTaskRowParameter("scheduled", app: app)
        XCTAssertEqual(app.switches["scheduled-has-time"].firstMatch.value as? String, "0")
        screenshot("Browsed day capture is untimed with no project", app: app)
        app.buttons["close-row-parameter"].tap()
        taskEditorSaveButton(app).tap()
        XCTAssertTrue(taskRow(named: "Buy milk from the market", app: app).waitForExistence(timeout: 10))
        screenshot("Tasks saved on browsed day", app: app)
        openWorkspaceView("Inbox", app: app)
        XCTAssertTrue(taskRow(named: "Deadline orphan", app: app).waitForExistence(timeout: 10))
        XCTAssertFalse(taskRow(named: "Buy milk from the market", app: app).exists)
        XCTAssertFalse(taskRow(named: "Project backlog", app: app).exists)
        XCTAssertFalse(taskRow(named: "Project scheduled", app: app).exists)
        screenshot("Inbox keeps Deadline-only orphan", app: app)
        try capture("Inbox capture", project: "Not set", scheduled: "Not set", app: app)
        openWorkspaceView("Projects", app: app)
        app.buttons["project-Work"].tap()
        XCTAssertTrue(taskRow(named: "Project backlog", app: app).waitForExistence(timeout: 10))
        XCTAssertTrue(taskRow(named: "Project scheduled", app: app).exists)
        screenshot("Project includes scheduled and unscheduled work", app: app)
        try capture("Project capture", project: "Work", scheduled: "Not set", app: app)
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "TSK_TEST_RECORDED_RECURRENCE")
        app.launch()
        XCTAssertTrue(pill.waitForExistence(timeout: 10))
        pill.swipeLeft()
        assertPlannerDay(String(Int(capturedDay.timeIntervalSince1970)), app: app)
        for (name, project, scheduled) in [("Buy milk from the market", "Not set", scheduledValue), ("Inbox capture", "Not set", "Not set"), ("Project capture", "Work", "Not set")] {
            if name == "Inbox capture" { openWorkspaceView("Inbox", app: app) }
            if name == "Project capture" {
                openWorkspaceView("Projects", app: app)
                app.buttons["project-Work"].tap()
            }
            let row = taskRow(named: name, app: app)
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            row.tap()
            XCTAssertTrue(app.buttons["row-project"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.buttons["row-project"].value as? String, project)
            XCTAssertEqual(app.buttons["row-scheduled"].value as? String, scheduled)
            screenshot("Durable " + name, app: app)
            tapTaskControl(app.buttons["collapse-task-row"], app: app)
            XCTAssertTrue(app.textFields["task-description"].waitForNonExistence(timeout: 5))
        }
        screenshot("Tasks after relaunch", app: app)
        openWorkspaceView("Today", app: app)
        pill.swipeLeft()
        assertPlannerDay(String(Int(capturedDay.timeIntervalSince1970)), app: app)
        openTaskInformation(taskRow(named: "Buy milk from the market", app: app), app: app)
        let savedDescription = app.staticTexts["task-detail-description"]
        XCTAssertTrue(savedDescription.waitForExistence(timeout: 5))
        XCTAssertEqual(savedDescription.label, "Buy milk from the market")
        XCTAssertTrue(app.descendants(matching: .any)["task-detail-status"].label.contains("Pending"))
        XCTAssertFalse(app.staticTexts["Identity"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "raw-attribute-")).firstMatch.exists)
        screenshot("Saved task information", app: app)
        app.terminate()
        let saved = try await storedTasks(app, checkpoint: "saved")
        XCTAssertEqual(saved.count, 6, "Only the three seeded and three saved tasks persist")
        let attributes = try XCTUnwrap(saved.values.first { $0["description"] == "Buy milk from the market" })
        XCTAssertEqual(attributes["scheduled"], String(Int(capturedDay.timeIntervalSince1970)))
        XCTAssertEqual(saved.values.first { $0["description"] == "Project capture" }?["project"], "Work")
        let inbox = try XCTUnwrap(saved.values.first { $0["description"] == "Inbox capture" })
        XCTAssertNil(inbox["scheduled"])
        XCTAssertTrue(inbox["project"]?.isEmpty ?? true)
        XCTAssertEqual(attributes["description"], "Buy milk from the market")
        XCTAssertEqual(attributes["status"], "pending")
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 10))
    }

    private func capture(_ title: String, project: String, scheduled: String, app: XCUIApplication) throws {
        app.buttons["New task"].tap()
        let description = app.textFields["task-description"]
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        description.typeText(title)
        tapTaskControlAtCenter(app.buttons["dismiss-row-keyboard"], app: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.buttons["row-project"].value as? String, project)
        XCTAssertEqual(app.buttons["row-scheduled"].value as? String, scheduled)
        screenshot(title + " defaults", app: app)
        tapTaskControlAtCenter(app.buttons["collapse-task-row"], app: app)
        XCTAssertTrue(description.waitForNonExistence(timeout: 5))
        XCTAssertTrue(taskRow(named: title, app: app).waitForExistence(timeout: 10))
    }

    private func screenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
