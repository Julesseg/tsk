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

    func testExpansionKeepsHeaderInPlace() throws {
        let app = try launch()
        let compactTitle = app.buttons["task-" + taskID]
        let checkbox = app.buttons["complete-task-row-" + taskID]
        XCTAssertTrue(compactTitle.waitForExistence(timeout: 10))
        let titleFrame = CGRect(x: compactTitle.frame.minX, y: compactTitle.frame.minY, width: compactTitle.frame.width, height: 44)
        let checkboxFrame = checkbox.frame
        XCTAssertEqual(checkboxFrame.midY, compactTitle.frame.midY, accuracy: 1, "Center the checkbox beside the title and metadata together")
        capture("Fixed header before expansion", app)
        app.buttons["task-" + taskID].tap()
        let title = app.textFields["task-description"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.frame.minX, titleFrame.minX, accuracy: 1)
        XCTAssertEqual(title.frame.minY, titleFrame.minY, accuracy: 1)
        XCTAssertEqual(checkbox.frame.minY, checkboxFrame.minY, accuracy: 1)
        XCTAssertLessThanOrEqual(app.buttons["row-project"].frame.minY, title.frame.maxY + 6,
                                 "Attribute controls replace the compact metadata line immediately below the title")
        XCTAssertTrue(checkbox.isEnabled, "Expanding a row must not apply disabled checkbox styling")
        XCTAssertFalse(app.buttons["collapse-task-row"].exists)
        capture("Fixed header with attributes revealed", app)
        try tapOutside(app)
        XCTAssertTrue(compactTitle.waitForExistence(timeout: 10))
        XCTAssertEqual(compactTitle.frame.minX, titleFrame.minX, accuracy: 1)
        XCTAssertEqual(compactTitle.frame.minY, titleFrame.minY, accuracy: 1)
        XCTAssertEqual(checkbox.frame.minY, checkboxFrame.minY, accuracy: 1)
        capture("Fixed header after collapse", app)
    }

    func testCompactControlsAndDateSurface() throws {
        let app = try launch()
        app.buttons["task-" + taskID].tap()
        XCTAssertTrue(app.textFields["task-description"].waitForExistence(timeout: 5))
        capture("Smaller attribute controls", app)
        for parameter in ["scheduled", "deadline", "waiting-date"] {
            openTaskRowParameter(parameter, app: app)
            XCTAssertTrue(app.datePickers[parameter + "-picker"].waitForExistence(timeout: 5))
            capture(parameter + " continuous glass surface", app)
            if parameter == "scheduled" { try tapOutsideParameter(app) }
            else { app.buttons["close-row-parameter"].tap() }
            XCTAssertTrue(app.datePickers[parameter + "-picker"].waitForNonExistence(timeout: 5))
            XCTAssertTrue(app.textFields["task-description"].exists)
        }
        capture("Controls restored after calendars", app)
        openTaskRowParameter("priority", app: app)
        capture("Native priority control and menu", app)
        tapTaskPickerOption("High", options: ["None", "Low", "Medium", "High"], app: app)
        openTaskRowParameter("project", app: app)
        capture("Native project control and menu", app)
        tapTaskPickerOption("New project…", options: ["No project", "Release", "New project…"], app: app)
        XCTAssertTrue(app.textFields["row-project-input"].waitForExistence(timeout: 5))
        capture("Native new project popover", app)
        app.buttons["close-row-parameter"].tap()
        XCTAssertTrue(app.textFields["row-project-input"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.textFields["task-description"].exists)
    }

    func testMiddleRowOpensSpaceAroundItsFixedHeader() throws {
        let app = try launch(neighbors: true)
        let rows = app.collectionViews["task-list"].cells
        XCTAssertEqual(rows.count, 3)
        let before = rows.element(boundBy: 0).frame
        let after = rows.element(boundBy: 2).frame
        let checkbox = app.buttons["complete-task-row-" + taskID]
        let header = checkbox.frame
        XCTAssertLessThanOrEqual(before.height, 53, "Compact rows use four points of padding on each edge")
        capture("Tighter list before middle row expansion", app)
        app.buttons["task-" + taskID].tap()
        XCTAssertTrue(app.textFields["task-description"].waitForExistence(timeout: 5))
        XCTAssertEqual(checkbox.frame.minY, header.minY, accuracy: 1)
        XCTAssertEqual(rows.element(boundBy: 0).frame.minY, before.minY - 12, accuracy: 1)
        XCTAssertGreaterThan(rows.element(boundBy: 2).frame.minY, after.minY + 12)
        capture("Middle row opens space above and below its fixed header", app)
        try tapOutside(app)
        XCTAssertTrue(app.buttons["task-" + taskID].waitForExistence(timeout: 10))
        XCTAssertEqual(checkbox.frame.minY, header.minY, accuracy: 1)
        XCTAssertEqual(rows.element(boundBy: 0).frame.minY, before.minY, accuracy: 1)
        XCTAssertEqual(rows.element(boundBy: 2).frame.minY, after.minY, accuracy: 1)
        capture("Tighter list restored after middle row collapse", app)
    }

    func testLongTitleUsesBoundedHeaderWithKeyboard() throws {
        let app = try launch(largeText: true, longTitle: true)
        app.buttons["task-" + taskID].tap()
        let title = app.textFields["task-description"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText(" updated")
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        if keyboard.frame.height > 0 { XCTAssertLessThanOrEqual(title.frame.maxY, keyboard.frame.minY) }
        XCTAssertLessThan(title.frame.height, app.frame.height / 2)
        XCTAssertTrue((title.value as? String ?? "").contains("updated"))
        capture("Long title scrolls within the bounded header", app)
    }

    func testOutsideSaveValidationPickerLayerAndDurableTitle() throws {
        let app = try launch()
        let row = app.buttons["task-" + taskID]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        capture("Collapsed surrounding list", app)
        row.tap()
        let title = app.textFields["task-description"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
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
        replaceTaskText(project, with: "Release.Next", app: app)
        capture("Project glass picker", app)
        let keyboard = app.keyboards.firstMatch
        tapTaskControlAtCenter(app.buttons["close-row-parameter"], app: app,
                               requiresVisibleKeyboard: keyboard.exists && !keyboard.frame.isEmpty)
        XCTAssertTrue(app.textFields["row-project-input"].waitForNonExistence(timeout: 5))
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
        openTaskRowParameter("priority", app: app)
        capture("Native priority menu after relaunch", app)
        tapTaskPickerOption("High", options: ["None", "Low", "Medium", "High"], app: app)
        capture("Dates persist independently after relaunch", app)
        openTaskRowParameter("deadline", app: app)
        XCTAssertTrue(app.datePickers["deadline-picker"].waitForExistence(timeout: 5))
        capture("Focused deadline control", app)
        app.buttons["close-row-parameter"].tap()
        openTaskRowParameter("waiting-date", app: app)
        XCTAssertTrue(app.datePickers["waiting-date-picker"].waitForExistence(timeout: 5))
        capture("Focused waiting-date control", app)
        app.buttons["close-row-parameter"].tap()
        closeTaskRow(app)
        XCTAssertTrue(title.waitForNonExistence(timeout: 10))
        let plainID = "A0000000-0000-0000-0000-000000000002"
        let circle = app.buttons["complete-task-row-" + plainID]
        let circleY = circle.frame.minY
        app.buttons["task-" + plainID].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(circle.frame.minY, circleY, accuracy: 1)
        capture("Plain task expands with anchored completion circle", app)
        closeTaskRow(app)
        XCTAssertTrue(title.waitForNonExistence(timeout: 10))
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
        closeTaskRow(app)
        let error = app.staticTexts["draft-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        let scroll = app.descendants(matching: .any)["task-row-editor"].firstMatch
        if !error.isHittable { scroll.swipeUp() }
        capture("Failed occurrence retains draft with internal overflow", app)
        XCTAssertTrue((title.value as? String ?? "").contains("unsaved"))
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

    func testRowNearBottomKeepsItsControlsAndFocusedTitleVisible() throws {
        let app = try launch(crowded: true)
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
        title.typeText(" scroll retained")
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

    private func launch(largeText: Bool = false, crowded: Bool = false, longTitle: Bool = false, neighbors: Bool = false) throws -> XCUIApplication {
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
