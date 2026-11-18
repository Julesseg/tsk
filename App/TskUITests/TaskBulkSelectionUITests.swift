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

    func testBulkDatesRequireApplyKeepMixedFieldsAndPersistAfterRelaunch() async throws {
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
        let cancelled = try await storedTasks(app, checkpoint: "cancelled")
        XCTAssertEqual(cancelled.count, 3)
        XCTAssertEqual(cancelled[first]?["scheduled"], "1792231200")
        XCTAssertEqual(cancelled[first]?["due"], "1792238400")
        XCTAssertNil(cancelled[second]?["scheduled"])
        XCTAssertNil(cancelled[second]?["due"])
        for id in [first, second, third] { XCTAssertEqual(cancelled[id]?["status"], "pending") }
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20))
        selectAllTasks(app)
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
        let saved = try await storedTasks(app, checkpoint: "applied")
        XCTAssertEqual(saved.count, 3)
        XCTAssertEqual(saved[first]?["scheduled"], "1792231200")
        XCTAssertNil(saved[first]?["due"])
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date(timeIntervalSince1970: 1792144800))!
        XCTAssertEqual(saved[second]?["scheduled"], String(Int(Calendar.current.startOfDay(for: tomorrow).timeIntervalSince1970)))
        XCTAssertNil(saved[second]?["due"])
        for id in [first, second, third] { XCTAssertEqual(saved[id]?["status"], "pending") }
        XCTAssertNil(saved[third]?["scheduled"])
        XCTAssertNil(saved[third]?["due"])

    }

    func testBulkDateFailureRetainsPendingOperationAndEverySelectedTask() async throws {
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
        let unchanged = try await storedTasks(app, checkpoint: "failed-apply")
        XCTAssertEqual(unchanged[first]?["scheduled"], "1792231200")
        XCTAssertEqual(unchanged[first]?["due"], "1792238400")
        XCTAssertNil(unchanged[second]?["scheduled"])
        XCTAssertNil(unchanged[second]?["due"])
        for id in [first, second, third] { XCTAssertEqual(unchanged[id]?["status"], "pending") }

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
        let row = app.buttons["task-" + first]
        let next = app.buttons["task-" + second]
        let deadline = ProcessInfo.processInfo.systemUptime + 10
        var previous: [CGRect]?
        var admitted: [CGRect]?
        var lastSample = "not sampled"
        func sample() -> Bool {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return false }
            let started = ProcessInfo.processInfo.systemUptime
            do {
                let snapshot = try app.snapshot()
                var nodes: [XCUIElementSnapshot] = []
                func collect(_ node: XCUIElementSnapshot) {
                    nodes.append(node)
                    for child in node.children { collect(child) }
                }
                collect(snapshot)
                guard !nodes.contains(where: { $0.identifier == "task-description" && $0.elementType == .textField || $0.identifier == "task-row-editor" && $0.elementType == .other }) else {
                    previous = nil
                    lastSample = "editor remains open"
                    return false
                }
                let targets = [("task-list", XCUIElement.ElementType.collectionView), ("task-" + first, .button), ("task-" + second, .button)]
                var frames: [CGRect] = []
                for (identifier, type) in targets {
                    let matches = nodes.filter { $0.identifier == identifier && $0.elementType == type }
                    guard matches.count == 1, let frame = matches.first?.frame, !frame.isEmpty else {
                        previous = nil
                        lastSample = "missing or ambiguous geometry: \(identifier) count=\(matches.count)"
                        return false
                    }
                    frames.append(frame)
                }
                lastSample = "frames=\(frames) snapshotSeconds=\(ProcessInfo.processInfo.systemUptime - started)"
                guard ProcessInfo.processInfo.systemUptime < deadline else { return false }
                let hittable = row.isHittable && next.isHittable
                lastSample += " hittable=\(hittable) totalSeconds=\(ProcessInfo.processInfo.systemUptime - started)"
                guard hittable, ProcessInfo.processInfo.systemUptime < deadline else {
                    previous = nil
                    return false
                }
                let stable = previous == frames
                previous = frames
                lastSample += " stable=\(stable)"
                if stable { admitted = frames }
                return stable
            } catch {
                previous = nil
                lastSample = "snapshot failed: \(error)"
                return false
            }
        }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in sample() }, object: nil)
        guard XCTWaiter.wait(for: [ready], timeout: max(0, deadline - ProcessInfo.processInfo.systemUptime)) == .completed,
              ProcessInfo.processInfo.systemUptime < deadline, let frames = admitted else {
            let detail = XCTAttachment(string: lastSample)
            detail.name = "Selection readiness admission"
            detail.lifetime = .keepAlways
            add(detail)
            XCTFail("Selection rows must settle before the native hold and sweep")
            return
        }
        let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frames[0].minX + 60, dy: frames[1].midY))
        let end = start.withOffset(CGVector(dx: 0, dy: frames[2].midY - frames[1].midY))
        start.press(forDuration: 0.8, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 1)
        XCTAssertTrue(app.buttons["task-selection-apply"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["task-selection-apply"].label, "2 selected")
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

    private func launch(invalidOccurrence: Bool = false, animationsEnabled: Bool = false, motionProbe: Bool = false) throws -> XCUIApplication {
        let app = taskTestApplication()
        app.launchArguments += ["-AppleLocale", "en_US", "-AppleLanguages", "(en)"]
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_NOW"] = "1792144800"
        app.launchEnvironment["TSK_TEST_CALENDAR_PRESENTATION"] = "empty"
        if motionProbe { app.launchEnvironment["TSK_TEST_SELECTION_MOTION"] = "1" }
        if animationsEnabled { app.launchEnvironment["TSK_UI_DISABLE_ANIMATIONS"] = "0" }
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
        app.launchEnvironment["TSK_TEST_RECORDED_RECURRENCE"] = String(decoding: try JSONSerialization.data(withJSONObject: records), as: UTF8.self)
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20))
        selectAllTasks(app)
        XCTAssertTrue(app.buttons["task-" + first].waitForExistence(timeout: 10))
        return app
    }
}
