import UIKit
import XCTest

@MainActor final class TaskBulkSelectionUITests: XCTestCase {
    private let first = "A0000000-0000-0000-0000-000000000001"
    private let second = "A0000000-0000-0000-0000-000000000002"
    private let third = "A0000000-0000-0000-0000-000000000003"

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
    }

    override func tearDownWithError() throws {
        XCUIApplication().terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testSelectionResolvesValidEditorAndRetainsInvalidDraft() throws {
        let app = try launch(crowded: true)
        let thirdRow = app.buttons["task-" + third]
        XCTAssertTrue(thirdRow.waitForExistence(timeout: 10))
        let selectionDistance = thirdRow.frame.midY - app.buttons["task-" + first].frame.midY
        app.buttons["task-" + first].tap()
        let title = app.textFields["task-description"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        replaceTaskText(title, with: " ", app: app)
        app.buttons["dismiss-row-keyboard"].tap()
        let list = app.collectionViews["task-list"]
        func selectExpandedRow(continuingVertically: Bool = false) {
            let circle = app.buttons["complete-task-row-" + first]
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: list.frame.minX + 24, dy: circle.frame.midY))
            start.press(forDuration: 0.8, thenDragTo: start.withOffset(CGVector(dx: 0, dy: continuingVertically ? selectionDistance : 0)), withVelocity: .slow, thenHoldForDuration: 1)
        }
        selectExpandedRow()
        XCTAssertTrue(app.staticTexts["draft-error"].waitForExistence(timeout: 10))
        XCTAssertTrue(title.exists)
        XCTAssertFalse(app.buttons["task-selection-apply"].exists)
        replaceTaskText(title, with: "Saved before selecting", app: app)
        app.buttons["dismiss-row-keyboard"].tap()
        selectExpandedRow(continuingVertically: true)
        XCTAssertTrue(title.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.buttons["task-selection-apply"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["task-selection-apply"].label, "3 selected")
        XCTAssertEqual(app.buttons["complete-task-row-" + third].value as? String, "Selected")
        XCTAssertTrue(taskRow(named: "Saved before selecting", app: app).exists)
        app.buttons["cancel-task-selection"].tap()
        app.buttons["task-" + first].tap()
        XCTAssertEqual(title.value as? String, "Saved before selecting")
        let circle = app.buttons["complete-task-row-" + first]
        let quickStart = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: list.frame.minX + 24, dy: circle.frame.midY))
        quickStart.press(forDuration: 0.8)
        XCTAssertTrue(title.waitForNonExistence(timeout: 10))
        XCTAssertEqual(app.buttons["task-selection-apply"].label, "1 selected")
        let row = app.buttons["task-" + first]
        let beforeScroll = row.frame.minY
        list.swipeUp()
        XCTAssertTrue(!row.exists || abs(row.frame.minY - beforeScroll) > 1, "An editor save finishing after release must restore scrolling")
        XCTAssertEqual(app.buttons["task-selection-apply"].label, "1 selected")
        app.buttons["cancel-task-selection"].tap()
    }

    func testBulkDatesRequireApplyKeepMixedFieldsAndPersistAfterRelaunch() throws {
        let app = try launch()
        selectPair(app)
        let scheduled = app.buttons["selection-scheduled"]
        let deadline = app.buttons["selection-deadline"]
        let complete = app.buttons["complete-task-selection"]
        XCTAssertFalse(app.buttons["workspace-settings"].exists)
        XCTAssertTrue(app.buttons["cancel-task-selection"].exists)
        XCTAssertEqual(scheduled.value as? String, "Unchanged")
        XCTAssertEqual(deadline.value as? String, "Unchanged")
        XCTAssertEqual(complete.value as? String, "Unchanged")
        for button in [scheduled, deadline, complete] {
            XCTAssertEqual(button.frame.width, button.frame.height, accuracy: 1)
        }
        XCTAssertEqual(scheduled.frame.maxX, deadline.frame.maxX, accuracy: 1)
        XCTAssertLessThan(scheduled.frame.maxY, deadline.frame.minY)
        XCTAssertEqual(app.buttons["task-selection-apply"].label, "2 selected")
        XCTAssertFalse(app.buttons["task-selection-apply"].isEnabled)
        XCTAssertFalse(app.buttons["reset-selection-scheduled"].exists)
        captureBulkDateEvidence("Neutral glass controls and toolbar cancellation", app: app)
        scheduled.tap()
        XCTAssertTrue(app.datePickers["scheduled-picker"].waitForExistence(timeout: 5))
        assertCompactPicker(app, field: "scheduled")
        XCTAssertFalse(app.buttons["reset-selection-date"].isEnabled)
        app.datePickers["scheduled-picker"].buttons["Sunday, October 18"].tap()
        XCTAssertTrue(app.buttons["reset-selection-date"].isEnabled)
        XCTAssertEqual(app.buttons["task-selection-apply"].label, "Apply to 2")
        XCTAssertTrue(app.buttons["task-selection-apply"].isEnabled)
        captureBulkDateEvidence("Glass Scheduled control expanded into date and time", app: app)
        let rowFrame = app.buttons["task-" + first].frame
        let outside = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: rowFrame.midX, dy: rowFrame.minY + 4))
        outside.tap()
        XCTAssertTrue(app.otherElements["selection-date-picker"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.buttons["task-selection-apply"].label, "Apply to 2", "An outside row tap closes the picker without changing selection")
        XCTAssertEqual(scheduled.value as? String, "Modified")
        scheduled.tap()
        let pickerFrame = app.otherElements["selection-date-picker"].frame
        let besidePicker = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: max(1, pickerFrame.minX / 2), dy: pickerFrame.midY))
        besidePicker.tap()
        XCTAssertTrue(app.otherElements["selection-date-picker"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.buttons["task-selection-apply"].label, "Apply to 2", "Empty space beside the picker also collapses it without changing selection")
        XCTAssertEqual(scheduled.value as? String, "Modified")
        app.buttons["task-" + third].tap()
        XCTAssertEqual(app.buttons["task-selection-apply"].label, "Apply to 3", "Row selection resumes after the picker closes")
        app.buttons["task-" + third].tap()
        XCTAssertEqual(app.buttons["task-selection-apply"].label, "Apply to 2")
        captureBulkDateEvidence("Collapsed pending value with neutral Reset", app: app)
        let reset = app.buttons["reset-selection-scheduled"]
        XCTAssertTrue(reset.isHittable)
        XCTAssertLessThan(reset.frame.maxX, scheduled.frame.maxX)
        reset.tap()
        XCTAssertEqual(scheduled.value as? String, "Unchanged")
        XCTAssertFalse(app.buttons["task-selection-apply"].isEnabled)
        XCTAssertEqual(app.buttons["task-selection-apply"].label, "2 selected")
        scheduled.tap()
        app.buttons["selection-date-today"].tap()
        app.buttons["close-selection-date"].tap()
        deadline.tap()
        assertCompactPicker(app, field: "deadline")
        app.buttons["selection-date-remove"].tap()
        app.buttons["close-selection-date"].tap()
        complete.tap()
        XCTAssertEqual(complete.value as? String, "Modified")
        captureBulkDateEvidence("Both dates and completion staged before X", app: app)
        app.buttons["cancel-task-selection"].tap()
        XCTAssertTrue(app.buttons["task-selection-apply"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["workspace-settings"].exists)
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "TSK_TEST_RECORDED_RECURRENCE")
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20))
        selectAllTasks(app)
        app.buttons["task-" + first].tap()
        XCTAssertTrue(app.buttons["row-scheduled"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["row-scheduled"].value as? String, formatted(1792231200))
        XCTAssertEqual(app.buttons["row-deadline"].value as? String, formatted(1792238400))
        closeTaskRow(app)
        selectPair(app)
        XCTAssertEqual(scheduled.value as? String, "Unchanged")
        XCTAssertEqual(deadline.value as? String, "Unchanged")
        XCTAssertEqual(complete.value as? String, "Unchanged")
        scheduled.tap()
        app.buttons["selection-date-tomorrow"].tap()
        app.buttons["close-selection-date"].tap()
        XCTAssertEqual(scheduled.value as? String, "Modified")
        scheduled.tap()
        XCTAssertEqual(app.buttons["selection-date-tomorrow"].value as? String, "Selected")
        app.buttons["reset-selection-date"].tap()
        app.buttons["close-selection-date"].tap()
        XCTAssertEqual(scheduled.value as? String, "Unchanged")
        XCTAssertFalse(app.buttons["task-selection-apply"].isEnabled)
        scheduled.tap()
        app.buttons["selection-date-tomorrow"].tap()
        app.buttons["close-selection-date"].tap()
        deadline.tap()
        app.buttons["selection-date-remove"].tap()
        app.buttons["close-selection-date"].tap()
        complete.tap()
        complete.tap()
        XCTAssertEqual(complete.value as? String, "Unchanged", "Toggling completion back removes its tint")
        captureBulkDateEvidence("Tinted dates remain pending until Apply", app: app)
        app.buttons["task-selection-apply"].tap()
        XCTAssertTrue(app.buttons["task-selection-apply"].waitForNonExistence(timeout: 10))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20))
        selectAllTasks(app)
        app.buttons["task-" + first].tap()
        XCTAssertTrue(app.buttons["row-scheduled"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["row-scheduled"].value as? String, formatted(1792231200))
        XCTAssertEqual(app.buttons["row-deadline"].value as? String, "Not set")
        closeTaskRow(app)
        tapTaskControlAtCenter(app.buttons["task-" + second], app: app)
        XCTAssertTrue(app.buttons["row-scheduled"].waitForExistence(timeout: 5))
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date(timeIntervalSince1970: 1792144800))!
        XCTAssertEqual(app.buttons["row-scheduled"].value as? String, formatted(Calendar.current.startOfDay(for: tomorrow).timeIntervalSince1970))
        XCTAssertEqual(app.buttons["row-deadline"].value as? String, "Not set")
    }

    func testBulkDateFailureRetainsPendingOperationAndEverySelectedTask() throws {
        let app = try launch(invalidOccurrence: true)
        selectPair(app)
        app.buttons["selection-scheduled"].tap()
        app.buttons["selection-date-remove"].tap()
        app.buttons["close-selection-date"].tap()
        app.buttons["selection-deadline"].tap()
        app.buttons["selection-date-tomorrow"].tap()
        app.buttons["close-selection-date"].tap()
        app.buttons["complete-task-selection"].tap()
        let apply = app.buttons["task-selection-apply"]
        apply.tap()
        let error = app.staticTexts["task-selection-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertTrue(error.isHittable)
        XCTAssertEqual(app.buttons["task-selection-apply"].label, "Apply to 2")
        for id in ["selection-scheduled", "selection-deadline", "complete-task-selection"] {
            XCTAssertEqual(app.buttons[id].value as? String, "Modified")
        }
        captureBulkDateEvidence("Apply failure retains every staged change and selected task", app: app)
        apply.tap()
        XCTAssertTrue(error.exists)
        app.buttons["cancel-task-selection"].tap()
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "TSK_TEST_RECORDED_RECURRENCE")
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Upcoming"].tap()
        XCTAssertEqual(upcomingRows(first, app: app).count, 2, "Failed Apply must preserve both original dates")
        selectAllTasks(app)
        XCTAssertTrue(app.buttons["task-" + first].exists)
        app.buttons["task-" + second].tap()
        XCTAssertTrue(app.buttons["row-scheduled"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["row-scheduled"].value as? String, "Not set")
        XCTAssertEqual(app.buttons["row-deadline"].value as? String, "Not set")
    }

    func testSelectionPickerValueChangesKeepQuickActionsStationary() throws {
        let app = try launch(animationsEnabled: true, motionProbe: true)
        selectPair(app)
        for field in ["scheduled", "deadline", "scheduled"] {
            app.buttons["selection-" + field].tap()
            XCTAssertTrue(app.otherElements["selection-date-picker"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.buttons.matching(identifier: "close-selection-date").count, 1)
            app.buttons["close-selection-date"].tap()
            XCTAssertTrue(app.otherElements["selection-date-picker"].waitForNonExistence(timeout: 5))
            XCTAssertFalse(app.buttons["close-selection-date"].exists)
            XCTAssertFalse(app.datePickers[field + "-picker"].exists)
        }
        app.buttons["selection-scheduled"].tap()
        let probe = app.otherElements["selection-picker-motion"]
        XCTAssertTrue(probe.waitForExistence(timeout: 5))
        func proof() -> [String: Any] {
            guard let value = probe.value as? String, let data = value.data(using: .utf8),
                  let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
            return result
        }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in proof()["ready"] as? Bool == true }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        captureBulkDateEvidence("Animation-enabled picker before value changes", app: app)
        app.datePickers["scheduled-picker"].buttons["Sunday, October 18"].tap()
        app.datePickers["scheduled-picker"].buttons["Tuesday, October 20"].tap()
        for id in ["selection-date-today", "selection-date-tomorrow", "selection-date-remove", "reset-selection-date"] {
            app.buttons[id].tap()
        }
        let measurements = proof()
        let attachment = XCTAttachment(string: String(describing: measurements))
        attachment.name = "Picker presentation-frame movement"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(measurements["changes"] as? Int), 6)
        XCTAssertLessThanOrEqual(try XCTUnwrap(measurements["maximumVerticalDrift"] as? Double), 1, "Value changes must not move the bottom actions during animation")
        captureBulkDateEvidence("Animation-enabled picker after value changes", app: app)
        app.buttons["close-selection-date"].tap()
        app.buttons["cancel-task-selection"].tap()
        XCTAssertTrue(app.buttons["task-selection-apply"].waitForNonExistence(timeout: 5))
    }

    private func selectPair(_ app: XCUIApplication) {
        let list = app.collectionViews["task-list"]
        let row = app.buttons["task-" + first]
        let next = app.buttons["task-" + second]
        var previous: [CGRect]?
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard !app.textFields["task-description"].exists, !app.otherElements["task-row-editor"].exists,
                  row.exists, next.exists, row.isHittable, next.isHittable else { previous = nil; return false }
            let frames = [list.frame, row.frame, next.frame]
            let stable = previous == frames && frames.allSatisfy { !$0.isEmpty }
            previous = frames
            return stable
        }, object: nil)
        guard XCTWaiter.wait(for: [ready], timeout: 10) == .completed else {
            XCTFail("Selection rows must settle before the native hold and sweep")
            return
        }
        let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: list.frame.minX + 60, dy: row.frame.midY))
        let end = start.withOffset(CGVector(dx: 0, dy: app.buttons["task-" + second].frame.midY - row.frame.midY))
        start.press(forDuration: 0.8, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 1)
        XCTAssertTrue(app.buttons["task-selection-apply"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["task-selection-apply"].label, "2 selected")
    }

    private func upcomingRows(_ id: String, app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", "upcoming-", id))
    }

    private func formatted(_ seconds: TimeInterval) -> String {
        Date(timeIntervalSince1970: seconds).formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: "en_US")))
    }

    private func captureBulkDateEvidence(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertCompactPicker(_ app: XCUIApplication, field: String, file: StaticString = #filePath, line: UInt = #line) {
        let actions = ["selection-date-today", "selection-date-tomorrow", "reset-selection-date", "selection-date-remove"].map { app.buttons[$0] }
        for action in actions {
            XCTAssertTrue(action.isHittable, "Every quick action is visible without scrolling", file: file, line: line)
            XCTAssertEqual(action.frame.midY, actions[0].frame.midY, accuracy: 1, file: file, line: line)
        }
        let calendar = app.datePickers[field + "-picker"]
        XCTAssertGreaterThanOrEqual(calendar.frame.minY, app.frame.minY, file: file, line: line)
        XCTAssertGreaterThanOrEqual(actions[0].frame.minY, calendar.frame.maxY, "Quick actions sit below the calendar", file: file, line: line)
        XCTAssertLessThanOrEqual(calendar.frame.maxY, app.frame.maxY, "The whole date/time picker fits on screen", file: file, line: line)
        XCTAssertTrue(app.buttons["close-selection-date"].isHittable, file: file, line: line)
    }

    private func launch(invalidOccurrence: Bool = false, crowded: Bool = false, animationsEnabled: Bool = false, motionProbe: Bool = false) throws -> XCUIApplication {
        let app = taskTestApplication()
        app.launchArguments += ["-AppleLocale", "en_US", "-AppleLanguages", "(en)"]
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_NOW"] = "1792144800"
        app.launchEnvironment["TSK_TEST_CALENDAR_PRESENTATION"] = "empty"
        if motionProbe { app.launchEnvironment["TSK_TEST_SELECTION_MOTION"] = "1" }
        if animationsEnabled { app.launchEnvironment["TSK_UI_DISABLE_ANIMATIONS"] = "0" }
        if crowded {
            app.launchEnvironment["TSK_TEST_SELECTION_EDITOR_DELAY"] = "1"
            app.launchEnvironment["TSK_UI_DIAGNOSTICS"] = "1"
        }
        var records: [[String: Any]] = []
        func add(_ id: String, _ attributes: [String: String]) {
            records.append(["id": id, "attributes": attributes.map { ["key": $0.key, "value": $0.value] }])
        }
        var attributes = ["description": "First selection task", "status": "pending", "scheduled": "1792231200", "due": "1792238400"]
        if invalidOccurrence {
            attributes["parent"] = "B0000000-0000-0000-0000-000000000001"
            attributes["imask"] = "0"
            add(attributes["parent"]!, ["status": "recurring", "mask": "?", "description": "Malformed series"])
        }
        add(first, attributes)
        add(second, ["description": "Second selection task", "status": "pending"])
        add(third, ["description": "Third selection task", "status": "pending"])
        if crowded {
            for index in 4...40 {
                add(String(format: "A0000000-0000-0000-0000-%012d", index), ["description": "Later selection task \(index)", "status": "pending"])
            }
        }
        app.launchEnvironment["TSK_TEST_RECORDED_RECURRENCE"] = String(decoding: try JSONSerialization.data(withJSONObject: records), as: UTF8.self)
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20))
        selectAllTasks(app)
        XCTAssertTrue(app.buttons["task-" + first].waitForExistence(timeout: 10))
        return app
    }
}
