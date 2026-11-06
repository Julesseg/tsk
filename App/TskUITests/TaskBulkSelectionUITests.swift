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

    func testLongPressSelectionDoesNotRequireNativeAccessibilityIdentifiers() throws {
        let app = try launch(animationsEnabled: true, nativeIdentifiers: false)
        app.buttons["task-" + first].press(forDuration: 0.8)
        let count = app.staticTexts["task-selection-count"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        XCTAssertEqual(count.label, "1 selected")
        XCTAssertFalse(app.buttons["start-task-" + first].exists, "Long press must select without presenting the former row menu")
        XCTAssertEqual(app.buttons["complete-task-row-" + first].value as? String, "Selected")
        app.buttons["task-" + first].press(forDuration: 0.8)
        XCTAssertTrue(count.waitForNonExistence(timeout: 5), "Deselecting the last task exits selection mode automatically")
        XCTAssertFalse(app.buttons["task-selection-done"].exists)
        XCTAssertFalse(app.buttons["complete-task-selection"].exists)
        XCTAssertEqual(app.buttons["complete-task-row-" + first].value as? String, "Not completed")
        app.buttons["task-" + first].press(forDuration: 0.8)
        XCTAssertEqual(count.label, "1 selected", "A fresh long press uses its own starting state")
        app.buttons["task-selection-done"].tap()
        XCTAssertTrue(count.waitForNonExistence(timeout: 5))
        app.buttons["task-" + first].press(forDuration: 0.8)
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        app.buttons["complete-task-row-" + first].tap()
        XCTAssertTrue(count.waitForNonExistence(timeout: 5), "Tapping the last selected circle also exits selection mode")
        app.buttons["task-" + first].tap()
        XCTAssertTrue(app.textFields["task-description"].waitForExistence(timeout: 5), "Ordinary task editing resumes after selection ends")
    }

    func testContinuousSelectionFreezesRowsBeforeReleaseAndCompletesDurably() throws {
        let app = try launch(probe: true)
        let list = app.collectionViews["task-list"]
        let initial = app.buttons["task-" + first].frame
        let last = app.buttons["task-" + third].frame
        let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: list.frame.minX + 60, dy: initial.midY))
        let end = start.withOffset(CGVector(dx: 0, dy: last.midY - initial.midY))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: list.frame.width * 0.7, dy: 0)), withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertFalse(app.staticTexts["task-selection-count"].exists)
        XCTAssertFalse(app.textFields["task-description"].exists, "A swipe without a hold must not select or open the editor")
        start.press(forDuration: 0.8, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 2)
        let count = app.staticTexts["task-selection-count"]
        let selectionAppeared = count.waitForExistence(timeout: 10)
        if !selectionAppeared {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Missing held selection after short swipe"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertTrue(selectionAppeared)
        XCTAssertEqual(count.label, "3 selected")
        let data = try XCTUnwrap((count.value as? String)?.data(using: .utf8))
        let proof = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "Held selection runtime proof"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(proof["selectedWhileTouchDown"] as? Bool, true)
        XCTAssertEqual(proof["maximumSelectedWhileTouchDown"] as? Int, 3)
        XCTAssertEqual(proof["scrollingDisabled"] as? Bool, true)
        XCTAssertEqual(proof["offsetsStable"] as? Bool, true)
        XCTAssertEqual(proof["rowsStable"] as? Bool, true)
        XCTAssertEqual(proof["refreshWhileTouchDown"] as? Bool, true)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(proof["activationDuration"] as? Double), 0.5)
        XCTAssertLessThanOrEqual(try XCTUnwrap(proof["activationDistance"] as? Double), 10, "Selection activates during the stationary hold, before vertical dragging")
        let width = try XCTUnwrap(proof["columnWidth"] as? Double)
        XCTAssertEqual(width, list.frame.width, accuracy: 2)
        if UIDevice.current.userInterfaceIdiom == .pad { XCTAssertLessThan(width, app.frame.width * 0.75) }
        XCTAssertTrue(taskRow(named: "Arrived while selecting", app: app).waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["task-" + first].frame.minX, initial.minX, accuracy: 1, "Rows stay horizontally fixed during selection")
        let circles = app.buttons.matching(identifier: "complete-task-row-" + second)
        circles.firstMatch.tap()
        XCTAssertEqual(count.label, "2 selected")
        func sweepBack() {
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: list.frame.minX + 60, dy: app.buttons["task-" + third].frame.midY))
            let end = start.withOffset(CGVector(dx: 0, dy: app.buttons["task-" + first].frame.midY - app.buttons["task-" + third].frame.midY))
            start.press(forDuration: 0.8, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 1)
        }
        sweepBack()
        XCTAssertTrue(count.waitForNonExistence(timeout: 5), "Deselecting every touched row exits selection mode")
        XCTAssertFalse(app.buttons["task-selection-done"].exists)
        XCTAssertFalse(app.buttons["complete-task-selection"].exists)
        sweepBack()
        XCTAssertEqual(count.label, "3 selected", "A new gesture starting on an unselected row adds every touched row")
        XCTAssertEqual(circles.firstMatch.value as? String, "Selected")
        circles.firstMatch.tap()
        XCTAssertEqual(count.label, "2 selected")
        circles.firstMatch.tap()
        XCTAssertEqual(count.label, "3 selected")
        let offset = app.buttons["task-" + first].frame.minY
        list.swipeUp()
        let firstRow = app.buttons["task-" + first]
        XCTAssertTrue(!firstRow.exists || abs(firstRow.frame.minY - offset) > 1, "Scrolling resumes after release")
        app.buttons["complete-task-selection"].tap()
        XCTAssertTrue(count.waitForNonExistence(timeout: 15))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20))
        selectDoneTasks(app)
        for name in ["First selection task", "Second selection task", "Third selection task"] {
            XCTAssertTrue(taskRow(named: name, app: app).waitForExistence(timeout: 10))
        }
    }

    func testUpcomingDuplicatesAndFailureKeepSelectionUntilDoneOrViewChange() throws {
        let app = try launch(invalidOccurrence: true)
        app.tabBars.buttons["Upcoming"].tap()
        let planned = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", "upcoming-planned-", first)).firstMatch
        XCTAssertTrue(planned.waitForExistence(timeout: 10))
        let list = app.collectionViews["upcoming-list"]
        let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: list.frame.minX + 60, dy: planned.frame.midY))
        start.press(forDuration: 0.8)
        let count = app.staticTexts["task-selection-count"]
        XCTAssertTrue(count.waitForExistence(timeout: 10))
        XCTAssertEqual(count.label, "1 selected")
        let circles = app.buttons.matching(identifier: "complete-task-row-" + first)
        XCTAssertEqual(circles.count, 2)
        for circle in circles.allElementsBoundByIndex { XCTAssertEqual(circle.value as? String, "Selected") }
        start.press(forDuration: 0.8)
        XCTAssertTrue(count.waitForNonExistence(timeout: 5), "Deselecting the last Upcoming task exits selection mode everywhere")
        for circle in circles.allElementsBoundByIndex { XCTAssertEqual(circle.value as? String, "Not completed") }
        start.press(forDuration: 0.8)
        XCTAssertEqual(count.label, "1 selected")
        circles.element(boundBy: 1).tap()
        XCTAssertTrue(count.waitForNonExistence(timeout: 5))
        start.press(forDuration: 0.8)
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        app.buttons["complete-task-selection"].tap()
        XCTAssertTrue(app.staticTexts["task-selection-error"].waitForExistence(timeout: 10))
        XCTAssertEqual(count.label, "1 selected")
        XCTAssertTrue(planned.exists)
        app.buttons["task-selection-done"].tap()
        XCTAssertTrue(count.waitForNonExistence(timeout: 5))
        start.press(forDuration: 0.8)
        XCTAssertTrue(count.waitForExistence(timeout: 10))
        selectAllTasks(app)
        XCTAssertTrue(count.waitForNonExistence(timeout: 5))
        app.buttons["complete-task-row-" + second].tap()
        XCTAssertTrue(app.buttons["task-" + second].waitForNonExistence(timeout: 15))
    }

    func testSelectionResolvesValidEditorAndRetainsInvalidDraft() throws {
        let app = try launch(crowded: true)
        app.buttons["task-" + first].tap()
        let title = app.textFields["task-description"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        replaceTaskText(title, with: " ", app: app)
        app.buttons["dismiss-row-keyboard"].tap()
        let list = app.collectionViews["task-list"]
        func selectExpandedRow(continuingVertically: Bool = false) {
            let circle = app.buttons["complete-task-row-" + first]
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: list.frame.minX + 24, dy: circle.frame.midY))
            start.press(forDuration: 0.8, thenDragTo: start.withOffset(CGVector(dx: 0, dy: continuingVertically ? 104 : 0)), withVelocity: .slow, thenHoldForDuration: 1)
        }
        selectExpandedRow()
        XCTAssertTrue(app.staticTexts["draft-error"].waitForExistence(timeout: 10))
        XCTAssertTrue(title.exists)
        XCTAssertFalse(app.staticTexts["task-selection-count"].exists)
        replaceTaskText(title, with: "Saved before selecting", app: app)
        app.buttons["dismiss-row-keyboard"].tap()
        selectExpandedRow(continuingVertically: true)
        XCTAssertTrue(title.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["task-selection-count"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["task-selection-count"].label, "3 selected")
        XCTAssertEqual(app.buttons["complete-task-row-" + third].value as? String, "Selected")
        XCTAssertTrue(taskRow(named: "Saved before selecting", app: app).exists)
        app.buttons["task-selection-done"].tap()
        app.buttons["task-" + first].tap()
        XCTAssertEqual(title.value as? String, "Saved before selecting")
        let circle = app.buttons["complete-task-row-" + first]
        let quickStart = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: list.frame.minX + 24, dy: circle.frame.midY))
        quickStart.press(forDuration: 0.8)
        XCTAssertTrue(title.waitForNonExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["task-selection-count"].label, "1 selected")
        let row = app.buttons["task-" + first]
        let beforeScroll = row.frame.minY
        list.swipeUp()
        XCTAssertTrue(!row.exists || abs(row.frame.minY - beforeScroll) > 1, "An editor save finishing after release must restore scrolling")
        XCTAssertEqual(app.staticTexts["task-selection-count"].label, "1 selected")
        app.buttons["task-selection-done"].tap()
    }

    func testBulkDatesRequireApplyKeepMixedFieldsAndPersistAfterRelaunch() throws {
        let app = try launch()
        selectPair(app)
        app.buttons["selection-scheduled"].tap()
        let apply = app.buttons["apply-selection-date"]
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        XCTAssertFalse(apply.isEnabled, "Opening mixed dates must not choose a replacement")
        app.buttons["selection-choose-day"].tap()
        app.datePickers["scheduled-picker"].buttons["Sunday, October 18"].tap()
        XCTAssertTrue(app.staticTexts["selection-date-pending"].exists)
        XCTAssertTrue(app.staticTexts["selection-date-pending"].isHittable)
        captureBulkDateEvidence("Calendar changes remain pending before Cancel", app: app)
        app.buttons["cancel-selection-date"].tap()
        app.buttons["task-selection-done"].tap()
        app.buttons["task-" + first].tap()
        XCTAssertTrue(app.buttons["row-scheduled"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["row-scheduled"].value as? String, formatted(1792231200))
        XCTAssertEqual(app.buttons["row-deadline"].value as? String, formatted(1792238400))
        closeTaskRow(app)
        selectPair(app)
        app.buttons["selection-scheduled"].tap()
        XCTAssertFalse(apply.isEnabled, "A dismissed operation must not be restored")
        app.buttons["selection-date-tomorrow"].tap()
        XCTAssertEqual(app.buttons["selection-date-tomorrow"].value as? String, "Selected")
        captureBulkDateEvidence("Scheduled pending explicit Apply", app: app)
        apply.tap()
        XCTAssertTrue(apply.waitForNonExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["task-selection-count"].label, "2 selected")
        captureBulkDateEvidence("Successful Apply retains selection", app: app)
        app.buttons["selection-deadline"].tap()
        XCTAssertFalse(apply.isEnabled)
        app.buttons["selection-date-remove"].tap()
        captureBulkDateEvidence("Deadline removal pending Apply", app: app)
        apply.tap()
        XCTAssertTrue(apply.waitForNonExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["task-selection-count"].label, "2 selected")
        app.buttons["task-selection-done"].tap()
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "TSK_TEST_RECORDED_RECURRENCE")
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20))
        selectAllTasks(app)
        app.buttons["task-" + first].tap()
        XCTAssertTrue(app.buttons["row-scheduled"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["row-scheduled"].value as? String, formatted(1792231200))
        XCTAssertEqual(app.buttons["row-deadline"].value as? String, "Not set")
        closeTaskRow(app)
        app.buttons["task-" + second].tap()
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
        let pending = app.staticTexts["selection-date-pending"]
        let original = pending.label
        let apply = app.buttons["apply-selection-date"]
        apply.tap()
        XCTAssertTrue(app.staticTexts["selection-date-error"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["selection-date-error"].isHittable, "The failure must be visible beside Apply without scrolling")
        XCTAssertTrue(pending.isHittable)
        XCTAssertEqual(pending.label, original)
        XCTAssertTrue(apply.isEnabled)
        captureBulkDateEvidence("Atomic failure retains pending operation", app: app)
        apply.tap()
        XCTAssertTrue(app.staticTexts["selection-date-error"].exists)
        app.buttons["cancel-selection-date"].tap()
        XCTAssertEqual(app.staticTexts["task-selection-count"].label, "2 selected")
        app.buttons["task-selection-done"].tap()
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "TSK_TEST_RECORDED_RECURRENCE")
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Upcoming"].tap()
        XCTAssertEqual(upcomingRows(first, app: app).count, 2, "Failure must preserve both original dates")
        selectAllTasks(app)
        app.buttons["task-" + second].tap()
        XCTAssertTrue(app.buttons["row-scheduled"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["row-scheduled"].value as? String, "Not set")
    }

    func testBulkDatesReconcileUpcomingByIdentityAndExitWhenNothingMatches() throws {
        let app = try launch()
        app.tabBars.buttons["Upcoming"].tap()
        let rows = upcomingRows(first, app: app)
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(rows.count, 2)
        rows.firstMatch.press(forDuration: 0.8)
        XCTAssertEqual(app.staticTexts["task-selection-count"].label, "1 selected")
        captureBulkDateEvidence("Upcoming selection action bar", app: app)
        app.buttons["selection-scheduled"].tap()
        app.buttons["selection-date-today"].tap()
        app.buttons["apply-selection-date"].tap()
        XCTAssertTrue(app.buttons["apply-selection-date"].waitForNonExistence(timeout: 10))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(app.staticTexts["task-selection-count"].label, "1 selected")
        app.buttons["selection-deadline"].tap()
        app.buttons["selection-date-remove"].tap()
        app.buttons["apply-selection-date"].tap()
        XCTAssertTrue(app.staticTexts["task-selection-count"].waitForNonExistence(timeout: 10))
        XCTAssertEqual(rows.count, 0)
        captureBulkDateEvidence("Upcoming exits selection when no tasks match", app: app)
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.buttons["task-" + first].waitForExistence(timeout: 10))
    }

    private func selectPair(_ app: XCUIApplication) {
        let list = app.collectionViews["task-list"]
        let row = app.buttons["task-" + first]
        let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: list.frame.minX + 60, dy: row.frame.midY))
        let end = start.withOffset(CGVector(dx: 0, dy: app.buttons["task-" + second].frame.midY - row.frame.midY))
        start.press(forDuration: 0.8, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 1)
        XCTAssertTrue(app.staticTexts["task-selection-count"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["task-selection-count"].label, "2 selected")
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

    private func launch(probe: Bool = false, invalidOccurrence: Bool = false, crowded: Bool = false, animationsEnabled: Bool = false, nativeIdentifiers: Bool = true) throws -> XCUIApplication {
        let app = taskTestApplication()
        app.launchArguments += ["-AppleLocale", "en_US", "-AppleLanguages", "(en)"]
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_NOW"] = "1792144800"
        app.launchEnvironment["TSK_TEST_CALENDAR_PRESENTATION"] = "empty"
        if probe {
            app.launchEnvironment["TSK_TEST_SELECTION_GESTURE"] = "1"
            app.launchEnvironment["TSK_UI_DISABLE_ANIMATIONS"] = "0"
        }
        if animationsEnabled { app.launchEnvironment["TSK_UI_DISABLE_ANIMATIONS"] = "0" }
        if !nativeIdentifiers { app.launchEnvironment["TSK_TEST_SELECTION_NATIVE_IDENTIFIERS"] = "0" }
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
        if probe || crowded {
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
