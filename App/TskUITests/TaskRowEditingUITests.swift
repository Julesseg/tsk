import UIKit
import XCTest

@MainActor final class TaskRowEditingUITests: XCTestCase {
    private let taskID = "A0000000-0000-0000-0000-000000000001"
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
    }
    override func tearDownWithError() throws {
        XCUIApplication().terminate()
        XCUIDevice.shared.orientation = .portrait
        XCUIDevice.shared.appearance = .light
    }

    func testMiddleRowOpensSpaceAroundItsFixedHeader() throws {
        let app = try launch(neighbors: true)
        let rows = app.collectionViews["task-list"].cells
        XCTAssertEqual(rows.count, 3)
        let before = rows.element(boundBy: 0).frame
        let after = rows.element(boundBy: 2).frame
        let checkbox = app.buttons["complete-task-row-" + taskID]
        let header = checkbox.frame
        let compact = app.buttons["task-" + taskID].frame
        XCTAssertLessThanOrEqual(before.height, 53, "Compact rows use four points of padding on each edge")
        capture("Tighter list before middle row expansion", app)
        _ = expandTask(app)
        XCTAssertEqual(checkbox.frame.minY, header.minY, accuracy: 1)
        XCTAssertEqual(rows.element(boundBy: 0).frame.minY, before.minY - 12, accuracy: 1)
        XCTAssertGreaterThan(rows.element(boundBy: 2).frame.minY, after.minY + 12)
        capture("Middle row opens space above and below its fixed header", app)
        try tapOutside(app)
        XCTAssertTrue(app.buttons["task-" + taskID].waitForExistence(timeout: 10))
        XCTAssertEqual(checkbox.frame.minY, header.minY, accuracy: 1)
        XCTAssertEqual(app.buttons["task-" + taskID].frame.minX, compact.minX, accuracy: 1)
        XCTAssertEqual(app.buttons["task-" + taskID].frame.minY, compact.minY, accuracy: 1)
        XCTAssertEqual(rows.element(boundBy: 0).frame.minY, before.minY, accuracy: 1)
        XCTAssertEqual(rows.element(boundBy: 2).frame.minY, after.minY, accuracy: 1)
        capture("Tighter list restored after middle row collapse", app)
    }

    func testOutsideSaveValidationPickersAndDurableCompletion() throws {
        let app = try launch()
        let row = app.buttons["task-" + taskID]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        capture("Collapsed surrounding list", app)
        let title = expandTask(app)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "task-row-editor").count, 1)
        capture("Expanded without keyboard", app)
        XCTAssertLessThan(app.buttons["row-project"].frame.minX, app.buttons["row-scheduled"].frame.minX)
        openTaskRowParameter("priority", app: app)
        capture("Native priority menu", app)
        tapTaskPickerOption("High", options: ["None", "Low", "Medium", "High"], app: app)
        openTaskRowParameter("project", app: app)
        capture("Native project menu", app)
        tapTaskPickerOption("New project…", options: ["No project", "Release", "New project…"], app: app)
        let project = app.textFields["row-project-input"]
        XCTAssertTrue(project.waitForExistence(timeout: 5))
        app.buttons["close-row-parameter"].tap()
        XCTAssertTrue(project.waitForNonExistence(timeout: 5))
        XCTAssertTrue(title.exists)
        openTaskRowParameter("project", app: app)
        tapTaskPickerOption("New project…", options: ["No project", "Release", "New project…"], app: app)
        XCTAssertTrue(project.waitForExistence(timeout: 5))
        replaceTaskText(project, with: "Release.Next", app: app)
        capture("Project glass picker", app)
        let keyboard = app.keyboards.firstMatch
        tapTaskControlAtCenter(app.buttons["close-row-parameter"], app: app,
                               requiresVisibleKeyboard: keyboard.exists && !keyboard.frame.isEmpty)
        XCTAssertTrue(app.textFields["row-project-input"].waitForNonExistence(timeout: 5))
        openTaskRowParameter("tags", app: app)
        let tagInput = app.textFields["row-tag-input"]
        XCTAssertTrue(tagInput.waitForExistence(timeout: 5))
        replaceTaskText(tagInput, with: "release", app: app)
        app.buttons["close-row-parameter"].tap()
        XCTAssertTrue(tagInput.waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.buttons["row-tags"].value as? String, "release")
        capture("Tags update the expanded draft", app)
        openTaskRowParameter("scheduled", app: app)
        XCTAssertTrue(app.datePickers["scheduled-picker"].waitForExistence(timeout: 5))
        capture("Direct Scheduled calendar", app)
        try tapOutsideParameter(app)
        XCTAssertTrue(title.exists)
        XCTAssertTrue(app.datePickers["scheduled-picker"].waitForNonExistence(timeout: 5))
        openTaskRowParameter("scheduled", app: app)
        app.datePickers["scheduled-picker"].buttons["Sunday, October 18"].tap()
        app.buttons["close-row-parameter"].tap()
        XCTAssertTrue(title.exists)
        XCTAssertTrue(app.datePickers["scheduled-picker"].waitForNonExistence(timeout: 5))
        replaceTaskText(title, with: " ", app: app)
        try tapOutside(app)
        XCTAssertTrue(app.staticTexts["draft-error"].waitForExistence(timeout: 5))
        XCTAssertTrue(title.exists)
        capture("Invalid title retains draft", app)
        replaceTaskText(title, with: "Release revised", app: app)
        XCTAssertLessThan(title.frame.maxY, app.keyboards.firstMatch.frame.minY)
        capture("Focused title above keyboard", app)
        app.buttons["dismiss-row-keyboard"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        try tapOutside(app)
        XCTAssertTrue(title.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.buttons["task-" + taskID].waitForExistence(timeout: 10))
        XCTAssertFalse(app.textFields["task-description"].exists, "Outside tap must not expand a dimmed neighbour")
        capture("Saved and collapsed", app)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20))
        selectAllTasks(app)
        XCTAssertTrue(taskRow(named: "Release revised", app: app).waitForExistence(timeout: 20))
        app.buttons["task-" + taskID].tap()
        XCTAssertTrue(app.buttons["row-scheduled"].waitForExistence(timeout: 5))
        XCTAssertTrue((app.buttons["row-deadline"].value as? String ?? "").contains("Oct"))
        XCTAssertEqual(app.buttons["row-project"].value as? String, "Release.Next")
        XCTAssertEqual(app.buttons["row-priority"].value as? String, "High")
        XCTAssertEqual(app.buttons["row-tags"].value as? String, "release")
        capture("Dates persist independently after relaunch", app)
        openTaskRowParameter("deadline", app: app)
        XCTAssertTrue(app.datePickers["deadline-picker"].waitForExistence(timeout: 5))
        capture("Focused deadline control", app)
        app.buttons["close-row-parameter"].tap()
        XCTAssertTrue(app.datePickers["deadline-picker"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(title.exists)
        openTaskRowParameter("waiting-date", app: app)
        XCTAssertTrue(app.datePickers["waiting-date-picker"].waitForExistence(timeout: 5))
        capture("Focused waiting-date control", app)
        app.buttons["close-row-parameter"].tap()
        XCTAssertTrue(app.datePickers["waiting-date-picker"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(title.exists)
        closeTaskRow(app)
        XCTAssertTrue(title.waitForNonExistence(timeout: 10))
        let plainID = "A0000000-0000-0000-0000-000000000002"
        let circleY = try visibleCompletionCircleFrame(plainID, app: app).minY
        app.buttons["task-" + plainID].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(try visibleCompletionCircleFrame(plainID, app: app).minY, circleY, accuracy: 1)
        capture("Plain task expands with anchored completion circle", app)
        closeTaskRow(app)
        XCTAssertTrue(title.waitForNonExistence(timeout: 10))
        openTaskInformation(taskRow(named: "Release revised", app: app), app: app)
        XCTAssertTrue(app.buttons["complete-task"].waitForExistence(timeout: 5))
        app.buttons["complete-task"].tap()
        XCTAssertTrue(app.buttons["complete-task"].waitForNonExistence(timeout: 5))
        capture("Completed detail", app)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20))
        XCTAssertFalse(taskRow(named: "Release revised", app: app).exists)
        selectDoneTasks(app)
        XCTAssertTrue(taskRow(named: "Release revised", app: app).waitForExistence(timeout: 10))
        capture("Completed task after relaunch", app)
    }

    func testUpcomingAnchorAndMembershipChangeAfterCollapse() throws {
        let app = try launch()
        app.tabBars.buttons["Upcoming"].tap()
        let planned = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "upcoming-planned-")).firstMatch
        XCTAssertTrue(planned.waitForExistence(timeout: 10))
        let identifier = planned.identifier
        planned.tap()
        XCTAssertTrue(app.textFields["task-description"].waitForExistence(timeout: 5))
        openTaskRowParameter("scheduled", app: app)
        app.buttons["remove-scheduled"].tap()
        XCTAssertTrue(app.staticTexts["Scheduled"].exists, "Draft edits must not regroup the anchored row")
        capture("Upcoming draft remains in its original group", app)
        openTaskRowParameter("deadline", app: app)
        app.buttons["remove-deadline"].tap()
        XCTAssertTrue(app.staticTexts["Deadlines"].exists)
        closeTaskRow(app)
        XCTAssertTrue(app.buttons[identifier].waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["No upcoming plans or deadlines"].waitForExistence(timeout: 10))
        capture("Upcoming membership applies after collapse", app)
    }

    func testOrganizationSelectionClearingInvalidTagsAndReopening() throws {
        let app = try launch(organized: true)
        let title = expandTask(app)
        XCTAssertEqual(app.buttons["row-project"].value as? String, "Release")
        XCTAssertEqual(app.buttons["row-priority"].value as? String, "Medium")
        XCTAssertEqual(app.buttons["row-tags"].value as? String, "review")
        capture("Populated organization components", app)
        openTaskRowParameter("tags", app: app)
        let input = app.textFields["row-tag-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["row-tag-review"].value as? String, "Selected")
        XCTAssertEqual(app.buttons["row-tag-accessibility"].value as? String, "Not selected")
        app.buttons["row-tag-review"].tap()
        app.buttons["row-tag-accessibility"].tap()
        capture("Existing tags can be removed and selected", app)
        replaceTaskText(input, with: "bad tag", app: app)
        app.buttons["row-add-tag"].tap()
        XCTAssertTrue(app.staticTexts["row-tag-error"].waitForExistence(timeout: 5))
        app.buttons["close-row-parameter"].tap()
        XCTAssertTrue(input.exists, "Done must retain invalid tag input")
        capture("Invalid tag retains picker and input", app)
        try tapOutsideParameter(app)
        XCTAssertTrue(input.waitForNonExistence(timeout: 5))
        XCTAssertTrue(title.exists, "Picker dismissal must leave the task open")
        closeTaskRow(app)
        XCTAssertTrue(app.staticTexts["draft-error"].waitForExistence(timeout: 5))
        XCTAssertTrue(title.exists, "Invalid unfinished tag must prevent collapse")
        openTaskRowParameter("tags", app: app)
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, "bad tag")
        replaceTaskText(input, with: "next", app: app)
        try tapOutsideParameter(app)
        XCTAssertTrue(input.waitForNonExistence(timeout: 5))
        closeTaskRow(app)
        XCTAssertTrue(title.waitForNonExistence(timeout: 10))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20))
        selectAllTasks(app)
        _ = expandTask(app)
        XCTAssertEqual(app.buttons["row-tags"].value as? String, "accessibility, next")
        capture("Tags persist after dismissal and relaunch", app)
        openTaskRowParameter("project", app: app)
        tapTaskPickerOption("No project", options: ["No project", "Release", "New project…"], app: app)
        openTaskRowParameter("priority", app: app)
        tapTaskPickerOption("None", options: ["None", "Low", "Medium", "High"], app: app)
        openTaskRowParameter("tags", app: app)
        app.buttons["row-tag-accessibility"].tap()
        app.buttons["row-tag-next"].tap()
        app.buttons["close-row-parameter"].tap()
        XCTAssertTrue(input.waitForNonExistence(timeout: 5))
        closeTaskRow(app)
        XCTAssertTrue(title.waitForNonExistence(timeout: 10))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20))
        selectAllTasks(app)
        _ = expandTask(app)
        for parameter in ["project", "priority", "tags"] {
            XCTAssertEqual(app.buttons["row-" + parameter].value as? String, "Not set")
        }
        XCTAssertTrue((app.buttons["row-deadline"].value as? String ?? "").contains("Oct"))
        capture("Cleared organization persists with dates unchanged", app)
    }

    func testOccurrenceFailureRetainsDraftAndLargeTextScrollsInsideRow() throws {
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_NOW"] = "1792144800"
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "TaskwarriorRecurringFixture", withExtension: "json"))
        var records = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        let parent = try XCTUnwrap(records.firstIndex { ($0["attributes"] as? [[String: String]] ?? []).contains { $0["key"] == "mask" } })
        var attributes = try XCTUnwrap(records[parent]["attributes"] as? [[String: String]])
        let mask = try XCTUnwrap(attributes.firstIndex { $0["key"] == "mask" })
        attributes[mask]["value"] = "WW?"; records[parent]["attributes"] = attributes
        app.launchEnvironment["TSK_TEST_RECORDED_RECURRENCE"] = String(decoding: try JSONSerialization.data(withJSONObject: records), as: UTF8.self)
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20))
        selectAllTasks(app)
        app.buttons["task-317F6B43-21B9-477D-86DE-920100159891"].tap()
        let title = app.textFields["task-description"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText(" unsaved")
        openTaskRowParameter("tags", app: app)
        let tagInput = app.textFields["row-tag-input"]
        XCTAssertTrue(tagInput.waitForExistence(timeout: 5))
        replaceTaskText(tagInput, with: "retained", app: app)
        app.buttons["close-row-parameter"].tap()
        XCTAssertTrue(tagInput.waitForNonExistence(timeout: 5))
        closeTaskRow(app)
        let error = app.staticTexts["draft-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        let scroll = app.descendants(matching: .any)["task-row-editor"].firstMatch
        if !error.isHittable { scroll.swipeUp() }
        capture("Failed occurrence retains draft with internal overflow", app)
        XCTAssertTrue((title.value as? String ?? "").contains("unsaved"))
        XCTAssertEqual(app.buttons["row-tags"].value as? String, "retained")
        XCTAssertFalse(app.buttons["collapse-task-row"].exists)
    }

    func testAppearanceAndAccessibilityOverflow() throws {
        for (appearance, largeText) in [("light", false), ("dark", false), ("light", true), ("dark", true)] {
            XCUIDevice.shared.appearance = appearance == "dark" ? .dark : .light
            let app = try launch(largeText: largeText)
            let mode = appearance + (largeText ? " accessibility XXXL" : "")
            capture("Collapsed " + mode, app)
            app.buttons["task-" + taskID].tap()
            XCTAssertTrue(app.textFields["task-description"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.keyboards.firstMatch.exists)
            capture("Expanded " + mode, app)
            openTaskRowParameter("tags", app: app)
            let input = app.textFields["row-tag-input"]
            XCTAssertTrue(input.waitForExistence(timeout: 5))
            capture("Tags picker " + mode, app)
            replaceTaskText(input, with: "release-accessibility-review", app: app)
            capture("Tags input above keyboard " + mode, app)
            app.buttons["close-row-parameter"].tap()
            XCTAssertTrue(input.waitForNonExistence(timeout: 5))
            XCTAssertEqual(app.buttons["row-tags"].value as? String, "release-accessibility-review")
            capture("Populated tags " + mode, app)
            openTaskRowParameter("scheduled", app: app)
            XCTAssertTrue(app.datePickers["scheduled-picker"].waitForExistence(timeout: 5))
            capture("Scheduled calendar " + mode, app)
            app.buttons["close-row-parameter"].tap()
            XCTAssertTrue(app.textFields["task-description"].exists)
            closeTaskRow(app)
            XCTAssertTrue(app.textFields["task-description"].waitForNonExistence(timeout: 10))
            app.terminate()
        }
    }

    func testLongTitleNearBottomKeepsKeyboardAndScrollingUsable() throws {
        let app = try launch(largeText: true, crowded: true, longTitle: true)
        let row = app.buttons["task-" + taskID]
        XCTAssertTrue(revealTaskElement(row, in: "task-list", app: app))
        capture("Lower-list row before expansion", app)
        row.tap()
        let title = app.textFields["task-description"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let information = app.buttons["task-row-information"]
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in information.isHittable && information.frame.maxY <= app.tabBars.firstMatch.frame.minY }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 5), .completed)
        XCTAssertLessThanOrEqual(information.frame.maxY, app.tabBars.firstMatch.frame.minY)
        capture("Lower-list row expanded within available height", app)
        title.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertLessThan(title.frame.maxY, app.keyboards.firstMatch.frame.minY)
        XCTAssertLessThan(title.frame.height, app.frame.height / 2)
        title.typeText(" scroll retained")
        XCTAssertTrue((title.value as? String ?? "").contains("scroll retained"))
        if app.keyboards.firstMatch.exists && app.keyboards.firstMatch.frame.height > 0 {
            tapTaskControlAtCenter(app.buttons["dismiss-row-keyboard"], app: app, requiresVisibleKeyboard: true)
        } else {
            tapTaskControl(app.buttons["dismiss-row-keyboard"], app: app)
        }
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        let list = app.collectionViews["task-list"]
        let originalY = title.frame.minY
        let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertTrue(!title.exists || title.frame.minY > originalY + 30, "The list must scroll from outside the expanded row without pinning it")
        XCTAssertFalse(app.buttons["task-" + taskID].exists, "Scrolling must not close the draft")
        capture("List scrolled while retaining the expanded draft", app)
        for _ in 0..<4 where !title.isHittable { list.swipeUp() }
        XCTAssertTrue(title.isHittable)
        XCTAssertTrue((title.value as? String ?? "").contains("scroll retained"))
        closeTaskRow(app)
        XCTAssertTrue(title.waitForNonExistence(timeout: 10))
    }

    private func visibleCompletionCircleFrame(_ id: String, app: XCUIApplication) throws -> CGRect {
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        var previous: CGRect?
        var accepted: CGRect?
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard ProcessInfo.processInfo.systemUptime < deadline,
                  let snapshot = try? app.snapshot(),
                  let circle = self.taskSnapshot("complete-task-row-" + id, type: .button, in: snapshot) else {
                previous = nil
                return false
            }
            let frame = circle.frame
            guard !frame.isNull, !frame.isInfinite, frame.minX.isFinite, frame.minY.isFinite,
                  frame.maxX.isFinite, frame.maxY.isFinite, frame.width > 0, frame.height > 0,
                  snapshot.frame.contains(frame), ProcessInfo.processInfo.systemUptime < deadline else {
                previous = nil
                return false
            }
            defer { previous = frame }
            guard previous == frame else { return false }
            accepted = frame
            return true
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: max(0, deadline - ProcessInfo.processInfo.systemUptime)), .completed)
        return try XCTUnwrap(accepted, "Completion-circle geometry must be finite, visible and stable before comparison")
    }

    private func expandTask(_ app: XCUIApplication) -> XCUIElement {
        let row = app.buttons["task-" + taskID]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let compact = row.frame
        let checkbox = app.buttons["complete-task-row-" + taskID]
        let circle = checkbox.frame
        XCTAssertEqual(circle.midY, compact.midY, accuracy: 1)
        row.tap()
        let title = app.textFields["task-description"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.frame.minX, compact.minX, accuracy: 1)
        XCTAssertEqual(title.frame.minY, compact.minY, accuracy: 1)
        XCTAssertEqual(checkbox.frame.minY, circle.minY, accuracy: 1)
        XCTAssertLessThanOrEqual(app.buttons["row-project"].frame.minY, title.frame.maxY + 6)
        XCTAssertTrue(checkbox.isEnabled)
        XCTAssertFalse(app.buttons["collapse-task-row"].exists)
        return title
    }

    private func launch(largeText: Bool = false, crowded: Bool = false, longTitle: Bool = false, neighbors: Bool = false, organized: Bool = false) throws -> XCUIApplication {
        let app = taskTestApplication()
        app.launchArguments += ["-AppleLocale", "en_US", "-AppleLanguages", "(en)"]
        app.launchEnvironment["TSK_UI_DISABLE_ANIMATIONS"] = nil
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_NOW"] = "1792144800"
        app.launchEnvironment["TSK_TEST_CALENDAR_PRESENTATION"] = "empty"
        var records: [[String: Any]] = [
            ["id": taskID, "attributes": ["description": "Prepare the release with the product team", "status": "pending", "project": "Release", "scheduled": "1792231200", "due": "1792238400", "opaque": "retain"].map { ["key": $0.key, "value": $0.value] }],
            ["id": "A0000000-0000-0000-0000-000000000002", "attributes": [["key": "description", "value": "Review accessibility findings"], ["key": "status", "value": "pending"]]]
        ]
        if organized {
            var attributes = try XCTUnwrap(records[0]["attributes"] as? [[String: String]])
            attributes += [["key": "priority", "value": "M"], ["key": "tag_review", "value": ""]]
            records[0]["attributes"] = attributes
            var otherAttributes = try XCTUnwrap(records[1]["attributes"] as? [[String: String]])
            otherAttributes.append(["key": "tag_accessibility", "value": ""])
            records[1]["attributes"] = otherAttributes
        }
        if longTitle {
            var attributes = try XCTUnwrap(records[0]["attributes"] as? [[String: String]])
            let description = try XCTUnwrap(attributes.firstIndex { $0["key"] == "description" })
            attributes[description]["value"] = String(repeating: "Review the release and accessibility findings with the product team. ", count: 16)
            records[0]["attributes"] = attributes
        }
        if crowded {
            for index in 1...24 {
                records.append(["id": String(format: "90000000-0000-0000-0000-%012d", index), "attributes": [["key": "description", "value": "Earlier task \(index) with a longer title to fill the list"], ["key": "status", "value": "pending"]]])
            }
        }
        if neighbors {
            records.append(["id": "90000000-0000-0000-0000-000000000001", "attributes": [["key": "description", "value": "Earlier task"], ["key": "status", "value": "pending"]]])
        }
        let data = try JSONSerialization.data(withJSONObject: records)
        app.launchEnvironment["TSK_TEST_RECORDED_RECURRENCE"] = String(decoding: data, as: UTF8.self)
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20))
        selectAllTasks(app)
        return app
    }

    private func tapOutside(_ app: XCUIApplication) throws {
        closeTaskRow(app)
    }

    private func tapOutsideParameter(_ app: XCUIApplication) throws {
        let frame = app.frame
        let top = max(frame.minY, app.navigationBars.allElementsBoundByIndex.map(\.frame.maxY).max() ?? frame.minY)
        var bottom = min(frame.maxY, app.tabBars.firstMatch.frame.minY)
        if app.keyboards.firstMatch.exists { bottom = min(bottom, app.keyboards.firstMatch.frame.minY) }
        let visible = CGRect(x: frame.minX, y: top, width: frame.width, height: max(0, bottom - top))
        let picker = app.descendants(matching: .any)["row-parameter-picker"].firstMatch.frame.intersection(visible)
        let regions = [
            CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: max(0, picker.minY - visible.minY)),
            CGRect(x: visible.minX, y: picker.maxY, width: visible.width, height: max(0, visible.maxY - picker.maxY)),
            CGRect(x: visible.minX, y: visible.minY, width: max(0, picker.minX - visible.minX), height: visible.height),
            CGRect(x: picker.maxX, y: visible.minY, width: max(0, visible.maxX - picker.maxX), height: visible.height)
        ].filter { !$0.isEmpty && !$0.isNull }
        let target = try XCTUnwrap(regions.max { $0.width * $0.height < $1.width * $1.height })
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: target.midX - frame.minX, dy: target.midY - frame.minY)).tap()
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Row editor " + name; shot.lifetime = .keepAlways; add(shot)
    }
}
