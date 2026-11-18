import XCTest

@MainActor
final class TaskScheduledUITests: XCTestCase {
    private let taskID = "A6400000-0000-0000-0000-000000000001"

    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { XCUIApplication().terminate() }

    func testNativeDraggingSavesLastCrossedIntentAndManualOrder() throws {
        let app = taskTestApplication()
        app.launchArguments += ["-AppleLocale", "en_US", "-AppleLanguages", "(en)"]
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_NOW"] = "1792144800"
        app.launchEnvironment["TSK_TEST_CALENDAR_PRESENTATION"] = "populated"
        app.launchEnvironment["TSK_TEST_NATIVE_DRAG"] = "1"
        app.launchEnvironment["TSK_UI_ISOLATED_SIMULATOR"] = "1"
        let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1792144800))
        let ids = (1...5).map { String(format: "A1060000-0000-0000-0000-%012d", $0) }
        let records: [[String: Any]] = ids.enumerated().map { index, id in
            var attributes = ["status": "pending", "description": ["Carried work", "Drag this task", "Untimed neighbor", "Timed neighbor", "Deadline fallback"][index], "project": "Drag", "entry": String(100 - index)]
            if index == 4 { attributes["due"] = "1792160000" }
            else { attributes["scheduled"] = String(Int(day.timeIntervalSince1970) + (index == 0 ? -86400 : index == 3 ? 3600 : 0)) }
            if index == 1 { attributes["due"] = "1792400000" }
            return ["id": id, "attributes": attributes.map { ["key": $0.key, "value": $0.value] }]
        }
        app.launchEnvironment["TSK_TEST_RECORDED_RECURRENCE"] = String(decoding: try JSONSerialization.data(withJSONObject: records), as: UTF8.self)
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20))
        openDragDay(app)
        let moving = app.buttons["task-" + ids[1]]
        let untimed = app.buttons["task-" + ids[2]]
        let fallback = app.buttons["task-" + ids[4]]
        XCTAssertTrue(fallback.waitForExistence(timeout: 10))
        XCTAssertLessThan(fallback.frame.midY, untimed.frame.midY)
        capture("Day rows before native drag", app: app)
        moving.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.8, thenDragTo: fallback.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)), withVelocity: .slow, thenHoldForDuration: 1)
        assertDragProof(app, lastCrossed: ids[4])
        moving.tap()
        XCTAssertTrue(app.buttons["row-scheduled"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["row-scheduled"].value as? String, formatted(1792160000))
        XCTAssertEqual(app.buttons["row-deadline"].value as? String, formatted(1792400000))
        app.buttons["collapse-task-row"].tap()
        XCTAssertGreaterThan(moving.frame.midY, fallback.frame.midY)
        capture("Native drop inherits Deadline fallback", app: app)
        let event = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "calendar-event-", "Design review with the product team")).firstMatch
        XCTAssertTrue(event.exists)
        XCTAssertGreaterThan(event.frame.midY, app.buttons["task-" + ids[3]].frame.midY)
        XCTAssertGreaterThan(event.frame.midY, fallback.frame.midY)
        moving.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.8, thenDragTo: event.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)), withVelocity: .slow, thenHoldForDuration: 1)
        assertDragProof(app, lastCrossed: "event:" + String(event.identifier.dropFirst("calendar-event-".count)))
        moving.tap()
        XCTAssertTrue(app.buttons["row-scheduled"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["row-scheduled"].value as? String, formatted(day.addingTimeInterval(36000).timeIntervalSince1970))
        XCTAssertEqual(app.buttons["row-deadline"].value as? String, formatted(1792400000))
        app.buttons["collapse-task-row"].tap()
        capture("Timed event crossing saves its complete start without editing Calendar", app: app)
        moving.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.8, thenDragTo: untimed.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)), withVelocity: .slow, thenHoldForDuration: 1)
        assertDragProof(app, lastCrossed: ids[2])
        XCTAssertLessThan(moving.frame.midY, untimed.frame.midY)
        capture("Upward crossing saves untimed intent before the neighbor", app: app)
        moving.tap()
        XCTAssertTrue(app.buttons["row-scheduled"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["row-scheduled"].value as? String, day.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(Locale(identifier: "en_US"))))
        XCTAssertEqual(app.buttons["row-deadline"].value as? String, formatted(1792400000))
        app.buttons["collapse-task-row"].tap()
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "TSK_TEST_RECORDED_RECURRENCE")
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20))
        openDragDay(app)
        XCTAssertTrue(moving.waitForExistence(timeout: 10))
        XCTAssertLessThan(moving.frame.midY, untimed.frame.midY)
        capture("Manual planner order survives relaunch", app: app)
        openWorkspaceView("Projects", app: app)
        app.buttons["project-Drag"].tap()
        XCTAssertTrue(moving.waitForExistence(timeout: 10))
        capture("Project rows before order-only drag", app: app)
        let projectLast = app.buttons["task-" + ids[4]]
        moving.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.8, thenDragTo: projectLast.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)), withVelocity: .slow, thenHoldForDuration: 1)
        assertDragProof(app, lastCrossed: ids[4])
        XCTAssertGreaterThan(moving.frame.midY, projectLast.frame.midY)
        moving.tap()
        XCTAssertEqual(app.buttons["row-scheduled"].value as? String, day.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(Locale(identifier: "en_US"))))
        XCTAssertEqual(app.buttons["row-deadline"].value as? String, formatted(1792400000))
        app.buttons["collapse-task-row"].tap()
        capture("Project drag keeps Scheduled and Deadline", app: app)
        touchScheduledSlot(ids[1], app: app)
        XCTAssertTrue(app.buttons["task-selection-apply"].waitForExistence(timeout: 5))
        capture("Scheduled slot selects in Project", app: app)
        touchScheduledSlot(ids[2], app: app)
        XCTAssertEqual(app.buttons["task-selection-apply"].label, "2 selected")
        let carried = app.buttons["task-" + ids[0]]
        capture("Selected project block before native lift", app: app)
        moving.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.8, thenDragTo: carried.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)), withVelocity: .slow, thenHoldForDuration: 1)
        assertDragProof(app, lastCrossed: ids[0], draggedIDs: [ids[2], ids[1]])
        XCTAssertLessThan(untimed.frame.midY, moving.frame.midY)
        XCTAssertLessThan(carried.frame.midY, untimed.frame.midY)
        XCTAssertEqual(app.buttons["task-selection-apply"].label, "2 selected")
        capture("Project block keeps visible relative order", app: app)
        app.buttons["cancel-task-selection"].tap()
        for id in [ids[2], ids[1]] {
            app.buttons["task-" + id].tap()
            XCTAssertEqual(app.buttons["row-scheduled"].value as? String, day.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(Locale(identifier: "en_US"))))
            if id == ids[1] { XCTAssertEqual(app.buttons["row-deadline"].value as? String, formatted(1792400000)) }
            app.buttons["collapse-task-row"].tap()
        }
        openDragDay(app)
        touchScheduledSlot(ids[1], app: app)
        let pill = app.buttons["planner-date-pill"]
        let originalDay = pill.value as? String
        pill.swipeLeft()
        XCTAssertEqual(pill.value as? String, originalDay)
        touchScheduledSlot(ids[2], app: app)
        XCTAssertEqual(app.buttons["task-selection-apply"].label, "2 selected")
        pill.swipeLeft()
        XCTAssertEqual(pill.value as? String, originalDay)
        capture("Selected day block before native lift", app: app)
        untimed.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.8, thenDragTo: fallback.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)), withVelocity: .slow, thenHoldForDuration: 1)
        assertDragProof(app, lastCrossed: ids[4], draggedIDs: [ids[1], ids[2]])
        XCTAssertLessThan(fallback.frame.midY, moving.frame.midY)
        XCTAssertLessThan(moving.frame.midY, untimed.frame.midY)
        XCTAssertEqual(app.buttons["task-selection-apply"].label, "2 selected")
        capture("Native selected block inherits last timed crossing", app: app)
        moving.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.8, thenDragTo: carried.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)), withVelocity: .slow, thenHoldForDuration: 1)
        assertDragProof(app, lastCrossed: ids[0], draggedIDs: [ids[1], ids[2]])
        XCTAssertLessThan(moving.frame.midY, untimed.frame.midY)
        XCTAssertLessThan(untimed.frame.midY, carried.frame.midY)
        XCTAssertFalse(app.buttons["Undo"].exists)
        XCTAssertEqual(pill.value as? String, originalDay)
        capture("Native selected block inherits original carryover intent", app: app)
        app.buttons["cancel-task-selection"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20))
        openDragDay(app)
        XCTAssertTrue(moving.waitForExistence(timeout: 10))
        XCTAssertLessThan(moving.frame.midY, untimed.frame.midY)
        XCTAssertLessThan(untimed.frame.midY, carried.frame.midY)
        for id in [ids[1], ids[2]] {
            app.buttons["task-" + id].tap()
            XCTAssertEqual(app.buttons["row-scheduled"].value as? String, day.addingTimeInterval(-86400).formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(Locale(identifier: "en_US"))))
            if id == ids[1] { XCTAssertEqual(app.buttons["row-deadline"].value as? String, formatted(1792400000)) }
            app.buttons["collapse-task-row"].tap()
        }
        capture("Selected block order and dates survive relaunch", app: app)
    }

    func testCompletedPlannerRowsRetainPageOrderAndCheckedStateAfterRelaunch() throws {
        let app = taskTestApplication()
        app.launchArguments += ["-AppleLocale", "en_US", "-AppleLanguages", "(en)"]
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_NOW"] = "1792144800"
        app.launchEnvironment["TSK_TEST_CALENDAR_PRESENTATION"] = "empty"
        let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1792144800))
        let future = Calendar.current.date(byAdding: .day, value: 2, to: day)!
        let ids = (1...4).map { String(format: "A1100000-0000-0000-0000-%012d", $0) }
        let records: [[String: Any]] = ids.enumerated().map { index, id in
            let date = index == 3 ? future : day.addingTimeInterval(-172800)
            let attributes = ["status": "pending", "description": ["Earlier carried neighbor", "Complete carried work", "Later carried neighbor", "Complete future work early"][index], "entry": String(900 - index), "scheduled": String(Int(date.timeIntervalSince1970)), "due": "1792400000"]
            return ["id": id, "attributes": attributes.map { ["key": $0.key, "value": $0.value] }]
        }
        app.launchEnvironment["TSK_TEST_RECORDED_RECURRENCE"] = String(decoding: try JSONSerialization.data(withJSONObject: records), as: UTF8.self)
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20))
        openWorkspaceView("Today", app: app)
        let row = app.buttons["task-" + ids[1]]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        capture("Carried work before completion", app: app)
        app.buttons["complete-task-row-" + ids[1]].tap()
        let checked = app.buttons["completed-task-row-" + ids[1]]
        let retained = checked.waitForExistence(timeout: 10)
        capture("Carried work after completion settles", app: app)
        XCTAssertTrue(retained)
        XCTAssertEqual(checked.value as? String, "Completed")
        XCTAssertLessThan(app.buttons["task-" + ids[0]].frame.midY, row.frame.midY)
        XCTAssertLessThan(row.frame.midY, app.buttons["task-" + ids[2]].frame.midY)
        app.buttons["planner-date-pill"].tap()
        app.buttons["planner-date-" + String(Int(future.timeIntervalSince1970))].tap()
        XCTAssertTrue(app.buttons["task-" + ids[3]].waitForExistence(timeout: 10))
        app.buttons["complete-task-row-" + ids[3]].tap()
        XCTAssertTrue(app.buttons["completed-task-row-" + ids[3]].waitForExistence(timeout: 10))
        capture("Early completion remains on its future day", app: app)
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "TSK_TEST_RECORDED_RECURRENCE")
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20))
        openWorkspaceView("Today", app: app)
        XCTAssertTrue(checked.waitForExistence(timeout: 10))
        XCTAssertLessThan(app.buttons["task-" + ids[0]].frame.midY, row.frame.midY)
        XCTAssertLessThan(row.frame.midY, app.buttons["task-" + ids[2]].frame.midY)
        capture("Carried checked history survives fixture-free relaunch", app: app)
        checked.tap()
        let reopened = app.buttons["complete-task-row-" + ids[1]]
        XCTAssertTrue(reopened.waitForExistence(timeout: 10))
        XCTAssertEqual(reopened.value as? String, "Not completed")
        XCTAssertLessThan(app.buttons["task-" + ids[0]].frame.midY, row.frame.midY)
        XCTAssertLessThan(row.frame.midY, app.buttons["task-" + ids[2]].frame.midY)
        capture("Pressing the completed checkmark reopens carried work", app: app)
        app.terminate()
        app.launch()
        XCTAssertTrue(reopened.waitForExistence(timeout: 10))
        XCTAssertEqual(reopened.value as? String, "Not completed")
        app.buttons["planner-date-pill"].tap()
        app.buttons["planner-date-" + String(Int(future.timeIntervalSince1970))].tap()
        XCTAssertTrue(app.buttons["completed-task-row-" + ids[3]].waitForExistence(timeout: 10))
        app.buttons["task-" + ids[3]].tap()
        XCTAssertEqual(app.buttons["row-scheduled"].value as? String, future.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(Locale(identifier: "en_US"))))
        XCTAssertEqual(app.buttons["row-deadline"].value as? String, formatted(1792400000))
        app.buttons["collapse-task-row"].tap()
        capture("Future checked history and original dates survive relaunch", app: app)
    }

    private func openDragDay(_ app: XCUIApplication) {
        openWorkspaceView("Today", app: app)
        assertTodayTaskList(app)
    }

    private func assertDragProof(_ app: XCUIApplication, lastCrossed: String, draggedIDs: [String]? = nil) {
        let list = app.collectionViews["task-list"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let value = list.value as? String, let data = value.data(using: .utf8),
                  let proof = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            return (proof["crossed"] as? [String])?.last == lastCrossed && proof["drops"] as? Int == 1
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed, "Native crossing/drop receipt: " + String(describing: list.value))
        let data = Data((list.value as? String ?? "{}").utf8)
        let proof = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if let draggedIDs {
            XCTAssertEqual(proof?["draggedIDs"] as? [String], draggedIDs)
            XCTAssertEqual(proof?["nativeItems"] as? Int, draggedIDs.count)
        }
        XCTAssertEqual(proof?["nativeSessions"] as? Int, 1)
        XCTAssertEqual(proof?["lifted"] as? Bool, true)
        XCTAssertEqual(proof?["originalsRetainedDuringCrossing"] as? Bool, true)
        XCTAssertFalse((proof?["displaced"] as? [String] ?? []).isEmpty, "Neighbors must move while the native drag is active")
    }

    func testNonMidnightScheduledEditsKeepOtherDatesAndPersist() async throws {
        let app = try launch()
        openWorkspaceView("Today", app: app)
        let todayRow = app.buttons["task-" + taskID]
        XCTAssertTrue(todayRow.waitForExistence(timeout: 10))
        let pill = app.buttons["planner-date-pill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        XCTAssertFalse(todayRow.label.contains("Scheduled Today"))
        XCTAssertTrue(todayRow.label.contains("Deadline Today"))
        capture("Persistent date pill with a full Today list", app: app)
        let originalDay = try XCTUnwrap(pill.value as? String)
        let tomorrowDay = Calendar.current.date(byAdding: .day, value: 1, to: Date(timeIntervalSince1970: Double(originalDay)!))!
        touchScheduledSlot(taskID, app: app)
        XCTAssertTrue(app.buttons["cancel-task-selection"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["task-selection-apply"].label, "1 selected")
        let list = app.collectionViews["task-list"]
        let background = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: list.frame.midX, dy: list.frame.midY))
        pill.swipeLeft()
        background.press(forDuration: 0.05, thenDragTo: background.withOffset(CGVector(dx: 150, dy: 0)), withVelocity: .slow, thenHoldForDuration: 0)
        assertPlannerDay(originalDay, app: app)
        capture("Selection suppresses pill and page day swipes", app: app)
        pill.tap()
        XCTAssertTrue(app.otherElements["planner-month-calendar"].waitForExistence(timeout: 5))
        capture("Selected task uses the expanded month calendar", app: app)
        app.buttons["planner-date-\(Int(tomorrowDay.timeIntervalSince1970))"].tap()
        XCTAssertTrue(app.otherElements["planner-month-calendar"].waitForNonExistence(timeout: 10))
        XCTAssertFalse(app.buttons["task-selection-apply"].exists, "Date tap saves immediately and clears selection")
        XCTAssertTrue(todayRow.waitForNonExistence(timeout: 10), "Scheduled work leaves its old day")
        XCTAssertEqual(pill.value as? String, originalDay, "Scheduling keeps the source day open")
        XCTAssertFalse(app.buttons["Undo"].exists)
        capture("Immediate scheduling clears selection and removes the source row", app: app)
        pill.tap()
        app.buttons["planner-date-\(Int(tomorrowDay.timeIntervalSince1970))"].tap()
        XCTAssertTrue(todayRow.waitForExistence(timeout: 10))
        todayRow.tap()
        XCTAssertTrue(app.buttons["row-scheduled"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["row-scheduled"].value as? String, formatted(1792257300))
        XCTAssertEqual(app.buttons["row-deadline"].value as? String, formatted(1792177200))
        XCTAssertEqual(app.buttons["row-waiting-date"].value as? String, formatted(1792184400))
        app.buttons["collapse-task-row"].tap()
        touchScheduledSlot(taskID, app: app)
        pill.tap()
        app.buttons["planner-date-\(originalDay)"].tap()
        XCTAssertTrue(todayRow.waitForNonExistence(timeout: 10))
        XCTAssertFalse(app.buttons["task-selection-apply"].exists)
        pill.tap()
        app.buttons["planner-date-\(originalDay)"].tap()
        XCTAssertTrue(todayRow.waitForExistence(timeout: 10))
        pill.swipeLeft()
        let tomorrowRow = app.buttons["task-A6400000-0000-0000-0000-000000000003"]
        XCTAssertTrue(tomorrowRow.waitForExistence(timeout: 10))
        XCTAssertNotEqual(pill.value as? String, originalDay)
        capture("Pill swipe reaches tomorrow", app: app)
        let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: list.frame.midX, dy: list.frame.midY))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 220, dy: 0)), withVelocity: .slow, thenHoldForDuration: 0)
        XCTAssertTrue(todayRow.waitForExistence(timeout: 10))
        XCTAssertEqual(pill.value as? String, originalDay)
        todayRow.swipeLeft()
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 5))
        XCTAssertEqual(pill.value as? String, originalDay, "Row swipe keeps the displayed day")
        capture("Row swipe Edit coexists with day navigation", app: app)
        pill.tap()
        XCTAssertTrue(app.otherElements["planner-month-calendar"].waitForExistence(timeout: 5))
        capture("Expanded month calendar", app: app)
        app.buttons["planner-date-\(Int(tomorrowDay.timeIntervalSince1970))"].tap()
        XCTAssertTrue(tomorrowRow.waitForExistence(timeout: 10))
        XCTAssertFalse(app.otherElements["planner-month-calendar"].exists)
        let future = tomorrowRow
        XCTAssertTrue(future.label.contains("Deadline Tomorrow"))
        let midnight = app.buttons["task-A6400000-0000-0000-0000-000000000002"]
        XCTAssertTrue(midnight.exists)
        XCTAssertLessThan(midnight.frame.minY, future.frame.minY)
        let row = app.buttons["task-" + taskID]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.buttons["row-scheduled"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["row-scheduled"].value as? String, formatted(1792170900))
        openTaskRowParameter("scheduled", app: app)
        XCTAssertTrue(app.datePickers["scheduled-picker"].waitForExistence(timeout: 5))
        let picker = app.datePickers["scheduled-picker"]
        let timeControl = picker.buttons.matching(NSPredicate(format: "label CONTAINS ':' OR value CONTAINS ':'")).firstMatch
        XCTAssertTrue(timeControl.exists, "Scheduled must expose its native time control: " + picker.debugDescription)
        picker.buttons["Sunday, October 18"].tap()
        app.buttons["close-row-parameter"].tap()
        XCTAssertEqual(app.buttons["row-scheduled"].value as? String, scheduled(on: 18))
        XCTAssertEqual(app.buttons["row-deadline"].value as? String, formatted(1792177200))
        XCTAssertEqual(app.buttons["row-waiting-date"].value as? String, formatted(1792184400))
        app.buttons["task-row-information"].tap()
        XCTAssertTrue(app.collectionViews["task-detail-form"].waitForExistence(timeout: 10))
        XCTAssertTrue(revealTaskElement(app.descendants(matching: .any)["task-planned-day"].firstMatch, in: "task-detail-form", app: app))
        app.buttons["edit-task"].tap()
        tapTaskControlAtCenter(app.buttons["dismiss-editor-keyboard"], app: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(revealTaskElement(app.datePickers["planned-day-picker"], in: "task-editor-form", app: app, bottomInset: app.buttons["dismiss-editor-keyboard"]))
        let tomorrow = app.buttons["plan-tomorrow"]
        XCTAssertTrue(revealTaskElement(tomorrow, in: "task-editor-form", app: app, initialScrollUp: false, bottomInset: app.buttons["dismiss-editor-keyboard"]))
        tomorrow.tap()
        app.buttons["save-task"].tap()
        XCTAssertTrue(app.buttons["edit-task"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        selectAllTasks(app)
        let midnightRow = app.buttons["task-A6400000-0000-0000-0000-000000000002"]
        XCTAssertTrue(midnightRow.waitForExistence(timeout: 10))
        midnightRow.tap()
        openTaskRowParameter("scheduled", app: app)
        setScheduledTime(true, app: app)
        capture("Explicit midnight selected in the inline editor", app: app)
        app.buttons["close-row-parameter"].tap()
        app.buttons["collapse-task-row"].tap()
        openWorkspaceView("Today", app: app)
        app.buttons["New task"].tap()
        let title = app.descendants(matching: .any)["task-description"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.typeText("Untimed scheduled capture")
        openTaskRowParameter("scheduled", app: app)
        XCTAssertEqual(app.switches["scheduled-has-time"].firstMatch.value as? String, "0")
        capture("Capture defaults to a Scheduled day without time", app: app)
        app.buttons["close-row-parameter"].tap()
        app.buttons["collapse-task-row"].tap()
        XCTAssertTrue(taskRow(named: "Untimed scheduled capture", app: app).waitForExistence(timeout: 10))
        app.terminate()
        let saved = try await storedTasks(app, checkpoint: "saved")
        let attributes = try XCTUnwrap(saved[taskID])
        var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date(timeIntervalSince1970: 1792170900))
        components.day = 17
        XCTAssertEqual(attributes["scheduled"], String(Int(try XCTUnwrap(Calendar.current.date(from: components)).timeIntervalSince1970)))
        XCTAssertEqual(attributes["due"], "1792177200")
        XCTAssertEqual(attributes["wait"], "1792184400")
        XCTAssertEqual(attributes["description"], "Review the release")
        XCTAssertEqual(attributes["status"], "pending")

        app.launchEnvironment.removeValue(forKey: "TSK_TEST_RECORDED_RECURRENCE")
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20))
        pill.tap()
        app.buttons["planner-date-\(Int(tomorrowDay.timeIntervalSince1970))"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.buttons["row-scheduled"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["row-scheduled"].value as? String, scheduled(on: 17))
        XCTAssertEqual(app.buttons["row-deadline"].value as? String, formatted(1792177200))
        XCTAssertEqual(app.buttons["row-waiting-date"].value as? String, formatted(1792184400))
        app.buttons["collapse-task-row"].tap()
        midnightRow.tap()
        openTaskRowParameter("scheduled", app: app)
        XCTAssertEqual(app.switches["scheduled-has-time"].firstMatch.value as? String, "1")
        capture("Explicit midnight survives relaunch", app: app)
        app.buttons["close-row-parameter"].tap()
        app.buttons["collapse-task-row"].tap()
        taskRow(named: "Untimed scheduled capture", app: app).tap()
        openTaskRowParameter("scheduled", app: app)
        XCTAssertEqual(app.switches["scheduled-has-time"].firstMatch.value as? String, "0")
        capture("Untimed capture survives relaunch", app: app)
        app.terminate()
    }

    private func setScheduledTime(_ enabled: Bool, app: XCUIApplication) {
        let toggle = app.switches["scheduled-has-time"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if (toggle.value as? String == "1") != enabled {
            let thumbs = toggle.switches.allElementsBoundByAccessibilityElement
            XCTAssertLessThanOrEqual(thumbs.count, 1)
            tapTaskControlAtCenter(thumbs.first ?? toggle, app: app)
        }
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", enabled ? "1" : "0"), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func formatted(_ seconds: TimeInterval) -> String {
        Date(timeIntervalSince1970: seconds).formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: "en_US")))
    }

    private func scheduled(on day: Int) -> String {
        var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date(timeIntervalSince1970: 1792170900))
        components.day = day
        return formatted(Calendar.current.date(from: components)!.timeIntervalSince1970)
    }

    private func launch() throws -> XCUIApplication {
        let app = taskTestApplication()
        app.launchArguments += ["-AppleLocale", "en_US", "-AppleLanguages", "(en)"]
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_NOW"] = "1792144800"
        app.launchEnvironment["TSK_TEST_CALENDAR_PRESENTATION"] = "empty"
        let todayFillers: [[String: Any]] = (1...18).map { index in
            ["id": String(format: "A6400000-0000-0000-0000-%012d", 100 + index),
             "attributes": ["description": "Later work \(index)", "status": "pending", "scheduled": String(1792170900 + index * 60)]]
        }
        let records: [[String: Any]] = ([
            ["id": taskID, "attributes": ["description": "Review the release", "status": "pending", "scheduled": "1792170900", "due": "1792177200", "wait": "1792184400", "dep_a6400000-0000-0000-0000-000000000006": "x"]],
            ["id": "A6400000-0000-0000-0000-000000000002", "attributes": ["description": "Midnight scheduled work", "status": "pending", "scheduled": String(Int(Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1792250100)).timeIntervalSince1970))]],
            ["id": "A6400000-0000-0000-0000-000000000003", "attributes": ["description": "Afternoon scheduled work", "status": "pending", "scheduled": "1792250100", "due": "1792257300"]],
            ["id": "A6400000-0000-0000-0000-000000000004", "attributes": ["description": "Carried untimed work", "status": "pending", "scheduled": String(Int(Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1792058400)).timeIntervalSince1970))]],
            ["id": "A6400000-0000-0000-0000-000000000005", "attributes": ["description": "Deadline fallback work", "status": "pending", "due": "1792160000"]],
            ["id": "A6400000-0000-0000-0000-000000000006", "attributes": ["description": "Untimed prerequisite", "status": "pending", "scheduled": String(Int(Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1792144800)).timeIntervalSince1970))]]
        ] + todayFillers).map { record in
            ["id": record["id"]!, "attributes": (record["attributes"] as! [String: String]).map { ["key": $0.key, "value": $0.value] }]
        }
        app.launchEnvironment["TSK_TEST_RECORDED_RECURRENCE"] = String(decoding: try JSONSerialization.data(withJSONObject: records), as: UTF8.self)
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20))
        return app
    }

}
