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

    func testScheduledSlotSelectsOnTouchDownAndSweepsWithoutMovingRows() throws {
        let app = try launch(plannerSlots: true)
        let firstRow = app.buttons["task-" + first]
        let thirdRow = app.buttons["task-" + third]
        let firstSlot = scheduledSlot(first, app: app)
        let count = app.buttons["task-selection-apply"]
        let list = app.collectionViews["task-list"]
        let pill = app.buttons["planner-date-pill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        XCTAssertLessThan(pill.frame.width, app.frame.width * 0.6)
        XCTAssertFalse(pill.frame.intersects(app.buttons["New task"].frame))
        XCTAssertTrue(thirdRow.waitForExistence(timeout: 10))
        XCTAssertLessThan(firstSlot.frame.maxX, firstRow.frame.minX)
        XCTAssertTrue(thirdRow.label.contains("Deadline Yesterday"))
        let deadlineToday = app.buttons["task-A0000000-0000-0000-0000-000000000027"]
        let allDay = app.buttons["task-A0000000-0000-0000-0000-000000000004"]
        XCTAssertTrue(deadlineToday.exists)
        let secondRow = app.buttons["task-" + second]
        XCTAssertLessThan(firstRow.frame.midY, thirdRow.frame.midY)
        XCTAssertLessThan(thirdRow.frame.midY, deadlineToday.frame.midY)
        XCTAssertLessThan(deadlineToday.frame.midY, allDay.frame.midY)
        XCTAssertLessThan(allDay.frame.midY, secondRow.frame.midY)
        let today: Date = Date(timeIntervalSince1970: 1792144800)
        XCTAssertEqual(scheduledSlot(second, app: app).label, "Scheduled " + today.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(Locale(identifier: "en_US"))))
        let rowFrames = [firstRow, thirdRow].map(\.frame)
        captureBulkDateEvidence("Scheduled times, carryover and separate deadlines", app: app)
        let settings = app.buttons["workspace-settings"].frame
        expandPlannerCalendar(app)
        captureBulkDateEvidence("Month calendar follows the upward pull", app: app)
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: settings.midX, dy: settings.midY)).tap()
        XCTAssertTrue(app.otherElements["planner-month-calendar"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.collectionViews["workspace-settings-list"].exists)
        pill.tap()
        XCTAssertTrue(app.otherElements["planner-month-calendar"].waitForExistence(timeout: 5))
        let day = try XCTUnwrap(pill.value as? String)
        let date = Date(timeIntervalSince1970: try XCTUnwrap(TimeInterval(day)))
        let tomorrow = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: date))
        let next = String(Int(tomorrow.timeIntervalSince1970))
        tapTaskControl(app.buttons["planner-date-" + next], app: app)
        XCTAssertTrue(app.otherElements["planner-month-calendar"].waitForNonExistence(timeout: 5))
        assertPlannerDay(next, app: app)
        pill.tap()
        let calendar = app.otherElements["planner-month-calendar"]
        XCTAssertTrue(calendar.waitForExistence(timeout: 5))
        XCTAssertFalse(calendar.buttons["Today"].exists)
        captureBulkDateEvidence("Expanded calendar away from Today", app: app)
        let nextMonth = try XCTUnwrap(Calendar.current.date(byAdding: .month, value: 1, to: tomorrow))
        let nextMonthButton = app.buttons["planner-date-\(Int(nextMonth.timeIntervalSince1970))"]
        let monthCenter = calendar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        monthCenter.press(forDuration: 0.05, thenDragTo: monthCenter.withOffset(CGVector(dx: -28, dy: 0)),
                          withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertFalse(nextMonthButton.exists)
        XCTAssertTrue(app.buttons["planner-date-" + next].isHittable)
        calendar.swipeLeft()
        XCTAssertTrue(nextMonthButton.waitForExistence(timeout: 5))
        XCTAssertEqual(pill.value as? String, next)
        captureBulkDateEvidence("Swipe opens the following month", app: app)
        calendar.swipeRight()
        XCTAssertTrue(app.buttons["planner-date-" + next].waitForExistence(timeout: 5))
        pill.tap()
        XCTAssertTrue(calendar.waitForNonExistence(timeout: 5))
        pill.press(forDuration: 0.7)
        assertPlannerDay(day, app: app)
        XCTAssertFalse(calendar.exists)
        pill.swipeLeft()
        assertPlannerDay(next, app: app)
        pill.swipeRight()
        assertPlannerDay(day, app: app)
        touchScheduledSlot(first, app: app)
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        XCTAssertEqual(count.label, "1 selected")
        app.buttons["cancel-task-selection"].tap()
        let start = firstSlot.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let last = scheduledSlot("A0000000-0000-0000-0000-000000000027", app: app)
        let end = start.withOffset(CGVector(dx: 0, dy: last.frame.midY - firstSlot.frame.midY))
        start.press(forDuration: 0.02, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertEqual(count.label, "3 selected")
        let data = try XCTUnwrap((count.value as? String)?.data(using: .utf8))
        let proof = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "Scheduled slot touch-down and sweep"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(proof["selectedWhileTouchDown"] as? Bool, true)
        XCTAssertEqual(proof["maximumSelectedWhileTouchDown"] as? Int, 3)
        XCTAssertEqual(proof["scrollingDisabled"] as? Bool, true)
        XCTAssertEqual(proof["offsetsStable"] as? Bool, true)
        XCTAssertEqual(proof["rowsStable"] as? Bool, true)
        XCTAssertLessThan(try XCTUnwrap(proof["activationDuration"] as? Double), 0.15)
        XCTAssertEqual(try XCTUnwrap(proof["columnWidth"] as? Double), firstSlot.frame.width, accuracy: 2)
        XCTAssertEqual([firstRow, thirdRow].map(\.frame), rowFrames)
        captureBulkDateEvidence("Sweep selects three rows in place", app: app)
        end.press(forDuration: 0.02, thenDragTo: start, withVelocity: .slow, thenHoldForDuration: 0)
        XCTAssertTrue(count.waitForNonExistence(timeout: 5))
        XCTAssertEqual([firstRow, thirdRow].map(\.frame), rowFrames)
        XCTAssertTrue(list.cells.allElementsBoundByIndex.contains { $0.frame.intersects(pill.frame) },
                      "Scrollable content extends behind the date pill")
        XCTAssertTrue(list.cells.allElementsBoundByIndex.contains { $0.frame.intersects(
            CGRect(x: app.frame.minX, y: app.frame.maxY - 12, width: app.frame.width, height: 12)) },
            "Rows extend into the bottom safe area")
        captureBulkDateEvidence("Task list extends behind the glass date pill", app: app)
        let scrollStart = list.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.7))
        let scrollEnd = scrollStart.withOffset(CGVector(dx: 0, dy: -240))
        scrollStart.press(forDuration: 0.05, thenDragTo: scrollEnd, withVelocity: .slow, thenHoldForDuration: 0)
        let scrolled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !firstRow.exists || firstRow.frame.minY < rowFrames[0].minY
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [scrolled], timeout: 5), .completed, "Scrolling resumes after release")

        openWorkspaceView("Inbox", app: app)
        XCTAssertEqual(pill.value as? String, "-")
        captureBulkDateEvidence("Inbox shows the compact date pill", app: app)
        pill.tap()
        XCTAssertTrue(calendar.waitForExistence(timeout: 5))
        tapTaskControl(app.buttons["planner-date-" + next], app: app)
        assertPlannerDay(next, app: app)
        openWorkspaceView("Projects", app: app)
        XCTAssertEqual(pill.value as? String, "-")
        pill.tap()
        XCTAssertTrue(calendar.waitForExistence(timeout: 5))
        captureBulkDateEvidence("The date pill opens above the Projects list", app: app)
        pill.tap()
        XCTAssertTrue(calendar.waitForNonExistence(timeout: 5))
        app.buttons["project-Work"].tap()
        let projectOpened = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Work"),
                                                      object: app.staticTexts["workspace-title-text"])
        XCTAssertEqual(XCTWaiter.wait(for: [projectOpened], timeout: 5), .completed)
        XCTAssertEqual(pill.value as? String, "-")
        pill.press(forDuration: 0.7)
        assertTodayTaskList(app)
        assertPlannerDay(day, app: app)
    }

    func testBulkDateFailureRetainsPendingOperationAndEverySelectedTask() async throws {
        let app = try launch(invalidOccurrence: true)
        selectPair(app)
        let pill = app.buttons["planner-date-pill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        pill.tap()
        let destination = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1792144800))
        let date = app.buttons["planner-date-\(Int(destination.timeIntervalSince1970))"]
        XCTAssertTrue(date.waitForExistence(timeout: 5))
        date.tap()
        XCTAssertTrue(app.staticTexts["task-selection-error"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.otherElements["planner-month-calendar"].exists)
        let saturday = Calendar.current.date(byAdding: .day, value: 1, to: destination)!
        let lastColumn = app.buttons["planner-date-\(Int(saturday.timeIntervalSince1970))"]
        XCTAssertLessThanOrEqual(lastColumn.frame.maxX, app.frame.maxX, "Calendar dates remain inside the task viewport after failure")
        XCTAssertTrue(lastColumn.isHittable)
        XCTAssertEqual(app.buttons["task-selection-apply"].label, "2 selected")
        for id in [first, second] {
            XCTAssertEqual(app.buttons["complete-task-row-" + id].value as? String, "Selected")
        }
        captureBulkDateEvidence("Calendar failure retains the calendar and selected tasks", app: app)
        XCTAssertEqual(pill.frame.height, 44, accuracy: 1)
        pill.tap()
        XCTAssertTrue(app.otherElements["planner-month-calendar"].waitForNonExistence(timeout: 5))
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
        let includeTime = app.switches["selection-set-time"]
        let time = app.datePickers["selection-time-picker"]
        for field in ["scheduled", "deadline"] {
            if field == "deadline" { app.buttons["selection-deadline"].tap() }
            let calendar = app.datePickers[field + "-picker"]
            XCTAssertTrue(includeTime.waitForExistence(timeout: 5))
            XCTAssertEqual(includeTime.value as? String, "0")
            XCTAssertFalse(time.exists)
            XCTAssertLessThanOrEqual(calendar.frame.maxY, includeTime.frame.minY)
            captureBulkDateEvidence("Bulk \(field) opens without time", app: app)
            app.buttons["selection-date-tomorrow"].tap()
            XCTAssertEqual(includeTime.value as? String, "0")
            XCTAssertFalse(time.exists)
            setTime(true, toggle: includeTime)
            XCTAssertTrue(time.waitForExistence(timeout: 5))
            XCTAssertLessThanOrEqual(calendar.frame.maxY, includeTime.frame.minY)
            XCTAssertLessThanOrEqual(includeTime.frame.maxY, time.frame.minY)
            captureBulkDateEvidence("Bulk \(field) date and time separated by the toggle", app: app)
            app.buttons["close-selection-date"].tap()
            app.buttons["selection-" + field].tap()
            XCTAssertTrue(time.waitForExistence(timeout: 5))
            XCTAssertEqual(includeTime.value as? String, "1")
            setTime(false, toggle: includeTime)
            XCTAssertTrue(time.waitForNonExistence(timeout: 5))
            XCTAssertLessThanOrEqual(calendar.frame.maxY, includeTime.frame.minY)
            captureBulkDateEvidence("Bulk \(field) date without time", app: app)
            app.buttons["close-selection-date"].tap()
        }
        app.buttons["cancel-task-selection"].tap()
        XCTAssertTrue(app.buttons["task-selection-apply"].waitForNonExistence(timeout: 5))
    }

    func testPlannerInteractionFrameIntervals() throws {
        let app = try launch(animationsEnabled: true, plannerSlots: true, frameProbe: true)
        let pill = app.buttons["planner-date-pill"]
        let list = app.collectionViews["task-list"]
        let count = app.buttons["task-selection-apply"]
        let picker = app.otherElements["selection-date-picker"]
        let calendar = app.otherElements["planner-month-calendar"]
        let day = try XCTUnwrap(pill.value as? String)
        let today = Date(timeIntervalSince1970: try XCTUnwrap(TimeInterval(day)))
        let nextDay = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: today))
        let probe = app.descendants(matching: .any)["planner-frame-probe"].firstMatch
        XCTAssertTrue(probe.exists)
        func now() -> Int { Int((CACurrentMediaTime() * 1000).rounded()) }
        func record(_ name: String, _ action: () -> Void) throws {
            let start = now()
            action()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
            let end = now()
            let raw = try XCTUnwrap(probe.value as? String)
            let sections = raw.components(separatedBy: "|")
            let samples = sections[0].split(separator: " ").compactMap { Int($0) }
            let touches = try XCTUnwrap(sections.last).split(separator: " ").compactMap { Int($0) }
            XCTAssertEqual(touches.count % 2, 0)
            XCTAssertGreaterThan(try XCTUnwrap(samples.first), start)
            XCTAssertEqual(samples.count % 2, 1)
            let gaps = stride(from: 1, to: samples.count, by: 2).compactMap { index in
                (start...end).contains(samples[index]) ? samples[index + 1] : nil
            }
            let excess = gaps.reduce(0) { $0 + $1 - 17 }
            var touchWindows: [Range<Int>] = []
            for index in stride(from: 0, to: touches.count, by: 2) where (start..<end).contains(touches[index]) {
                let lower = max(touches[index], touchWindows.last?.upperBound ?? start)
                let upper = min(end, touches[index + 1] + 350)
                if lower < upper { touchWindows.append(lower..<upper) }
            }
            XCTAssertFalse(touchWindows.isEmpty)
            var touchExcess = 0
            for index in stride(from: 1, to: samples.count, by: 2) {
                let late = (samples[index] - samples[index + 1] + 17)..<samples[index]
                for window in touchWindows { touchExcess += late.clamped(to: window).count }
            }
            print("PLANNER-FRAMES \(name) elapsed=\(end - start) gaps=\(gaps.count) excessMs=\(excess) touchExcessMs=\(touchExcess) maxMs=\(gaps.max() ?? 0)")
        }

        let settings = app.buttons["workspace-settings"].frame
        let outside = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: settings.midX, dy: settings.midY))
        let firstRow = app.buttons["task-" + first]
        let navigationOnly = ProcessInfo.processInfo.environment["TSK_PLANNER_NAVIGATION_BENCHMARK"] == "1"
        for _ in 0..<(navigationOnly ? 5 : 3) {
            if !navigationOnly {
                let top = firstRow.frame.minY
                try record("scroll") {
                    list.swipeUp()
                    XCTAssertTrue(!firstRow.exists || firstRow.frame.minY < top - 4, "The scroll sample must move the list")
                    list.swipeDown()
                }
                XCTAssertTrue(scheduledSlot(first, app: app).isHittable)
            }
            try record("pages") {
                let center = pill.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                center.press(forDuration: 0.05, thenDragTo: center.withOffset(CGVector(dx: -155, dy: 0)), withVelocity: .fast, thenHoldForDuration: 0)
                assertPlannerDay(String(Int(nextDay.timeIntervalSince1970)), app: app)
                center.press(forDuration: 0.05, thenDragTo: center.withOffset(CGVector(dx: 155, dy: 0)), withVelocity: .fast, thenHoldForDuration: 0)
                assertPlannerDay(day, app: app)
            }
            try record("pill") {
                expandPlannerCalendar(app)
                outside.tap()
            }
            XCTAssertTrue(calendar.waitForNonExistence(timeout: 5))
            assertPlannerDay(day, app: app)
            if navigationOnly { continue }
            let start = scheduledSlot(first, app: app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let end = scheduledSlot(third, app: app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            try record("selection") { start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2) }
            XCTAssertEqual(count.label, "2 selected")
            for field in ["scheduled", "deadline"] {
                try record(field) {
                    app.buttons["selection-" + field].tap()
                    XCTAssertTrue(picker.waitForExistence(timeout: 5))
                    app.buttons["close-selection-date"].tap()
                }
                XCTAssertTrue(picker.waitForNonExistence(timeout: 5))
            }
            app.buttons["cancel-task-selection"].tap()
        }
        for delta in [8, 0] {
            let target = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: delta, to: today))
            let value = String(Int(target.timeIntervalSince1970))
            pill.tap()
            let button = app.buttons["planner-date-" + value]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            tapTaskControl(button, app: app)
            assertPlannerDay(value, app: app)
            XCTAssertTrue(calendar.waitForNonExistence(timeout: 5))
        }
    }

    private func setTime(_ enabled: Bool, toggle: XCUIElement) {
        XCTAssertTrue(toggle.exists)
        let thumb = toggle.switches.firstMatch
        if thumb.exists {
            thumb.coordinate(withNormalizedOffset: CGVector(dx: enabled ? 0.28 : 0.72, dy: 0.5)).tap()
        } else {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
                .withOffset(CGVector(dx: -25, dy: 0)).tap()
        }
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", enabled ? "1" : "0"), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
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
                guard !nodes.contains(where: { $0.identifier == "task-description" && $0.elementType == .textField || $0.identifier == "task-row-editor" }) else {
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
            XCTFail("Selection rows must settle before the scheduled-slot sweep")
            return
        }
        let start = scheduledSlot(first, app: app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 0, dy: frames[2].midY - frames[1].midY))
        start.press(forDuration: 0.02, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0)
        XCTAssertTrue(app.buttons["task-selection-apply"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["task-selection-apply"].label, "2 selected")
    }

    private func captureBulkDateEvidence(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launch(invalidOccurrence: Bool = false, animationsEnabled: Bool = false, motionProbe: Bool = false, plannerSlots: Bool = false, frameProbe: Bool = false) throws -> XCUIApplication {
        let app = taskTestApplication()
        app.launchArguments += ["-AppleLocale", "en_US", "-AppleLanguages", "(en)"]
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_NOW"] = "1792144800"
        app.launchEnvironment["TSK_TEST_CALENDAR_PRESENTATION"] = "empty"
        if frameProbe {
            app.launchEnvironment["TSK_TEST_PLANNER_FRAMES"] = "1"
            app.launchEnvironment["TSK_UI_ISOLATED_SIMULATOR"] = "1"
        }
        if plannerSlots && !frameProbe { app.launchEnvironment["TSK_TEST_SELECTION_GESTURE"] = "1" }
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
        if plannerSlots {
            let calendar = Calendar.current
            let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1792144800))
            let yesterday = calendar.date(byAdding: .day, value: -1, to: day)!
            let older = calendar.date(byAdding: .day, value: -1, to: yesterday)!
            func timestamp(_ date: Date) -> String { String(Int(date.timeIntervalSince1970)) }
            add(first, ["description": "Carried timed work", "status": "pending", "project": "Work", "scheduled": timestamp(older.addingTimeInterval(36_000))])
            add(second, ["description": "Carried untimed work", "status": "pending", "scheduled": timestamp(yesterday)])
            add(third, ["description": "Overdue deadline only", "status": "pending", "due": timestamp(yesterday.addingTimeInterval(72_000))])
            add("A0000000-0000-0000-0000-000000000004", ["description": "Untimed today", "status": "pending", "scheduled": timestamp(day)])
            add("A0000000-0000-0000-0000-000000000027", ["description": "Deadline only today", "status": "pending", "due": timestamp(day.addingTimeInterval(72_000))])
            for index in 5...26 {
                add(String(format: "A0000000-0000-0000-0000-%012d", index), [
                    "description": "Timed work \(index - 4)", "status": "pending", "scheduled": timestamp(day.addingTimeInterval(36_000 + Double(index * 60)))
                ])
            }
        } else {
            add(first, attributes)
            add(second, ["description": "Second selection task", "status": "pending"])
            add(third, ["description": "Third selection task", "status": "pending"])
        }
        app.launchEnvironment["TSK_TEST_RECORDED_RECURRENCE"] = String(decoding: try JSONSerialization.data(withJSONObject: records), as: UTF8.self)
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20))
        if !plannerSlots { selectAllTasks(app) }
        XCTAssertTrue(app.buttons["task-" + first].waitForExistence(timeout: 10))
        return app
    }
}
