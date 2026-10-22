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
        app.buttons["row-planned-day"].tap()
        XCTAssertTrue(app.buttons["plan-today"].waitForExistence(timeout: 5))
        capture("Focused planned-day choices", app)
        app.descendants(matching: .any)["dismiss-row-parameter-outside"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.1)).tap()
        XCTAssertTrue(title.exists)
        XCTAssertFalse(app.buttons["plan-today"].exists)
        app.buttons["row-planned-day"].tap()
        app.buttons["plan-tomorrow"].tap()
        XCTAssertTrue(title.exists)
        XCTAssertFalse(app.buttons["plan-today"].exists)
        replaceTaskText(title, with: " ", app: app)
        try tapOutside(app)
        XCTAssertTrue(app.staticTexts["draft-error"].waitForExistence(timeout: 5))
        XCTAssertTrue(title.exists)
        capture("Invalid title retains draft", app)
        replaceTaskText(title, with: "Release revised", app: app)
        XCTAssertLessThan(title.frame.maxY, app.keyboards.firstMatch.frame.minY)
        capture("Focused title above keyboard", app)
        app.buttons["dismiss-row-keyboard"].tap()
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
        XCTAssertTrue(app.buttons["row-deadline"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["row-deadline"].label.contains("Oct"))
        capture("Dates persist independently after relaunch", app)
        app.buttons["row-deadline"].tap()
        XCTAssertTrue(app.datePickers["deadline-picker"].waitForExistence(timeout: 5))
        capture("Focused deadline control", app)
        app.buttons["close-row-parameter"].tap()
        app.scrollViews["row-date-parameters"].swipeLeft()
        app.buttons["row-waiting-date"].tap()
        XCTAssertTrue(app.datePickers["waiting-date-picker"].waitForExistence(timeout: 5))
        capture("Focused waiting-date control", app)
        app.buttons["use-parameter-date"].tap()
        app.buttons["collapse-task-row"].tap()
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
        app.buttons["row-planned-day"].tap()
        app.buttons["remove-planned-day"].tap()
        XCTAssertTrue(app.staticTexts["Planned work"].exists, "Draft edits must not regroup the anchored row")
        capture("Upcoming draft remains in its original group", app)
        app.buttons["row-deadline"].tap()
        app.buttons["remove-deadline"].tap()
        XCTAssertTrue(app.staticTexts["Deadlines"].exists)
        app.buttons["collapse-task-row"].tap()
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
        app.buttons["collapse-task-row"].tap()
        let error = app.staticTexts["draft-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        let scroll = app.scrollViews["task-row-editor"]
        if !error.isHittable { scroll.swipeUp() }
        capture("Failed occurrence retains draft with internal overflow", app)
        XCTAssertTrue((title.value as? String ?? "").contains("unsaved"))
        XCTAssertTrue(app.buttons["collapse-task-row"].exists)
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
            app.buttons["row-planned-day"].tap()
            XCTAssertTrue(app.buttons["plan-today"].waitForExistence(timeout: 5))
            capture("Planned-day picker " + mode, app)
            app.buttons["close-row-parameter"].tap()
            XCTAssertTrue(app.textFields["task-description"].exists)
            app.buttons["collapse-task-row"].tap()
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
        XCTAssertTrue(information.isHittable)
        XCTAssertLessThanOrEqual(information.frame.maxY, app.tabBars.firstMatch.frame.minY)
        capture("Lower-list row expanded within available height", app)
        title.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertLessThan(title.frame.maxY, app.keyboards.firstMatch.frame.minY)
        app.buttons["collapse-task-row"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 10))
    }

    private func launch(largeText: Bool = false, crowded: Bool = false) throws -> XCUIApplication {
        let app = taskTestApplication()
        app.launchEnvironment["TSK_UI_DISABLE_ANIMATIONS"] = nil
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_NOW"] = "1792144800"
        app.launchEnvironment["TSK_TEST_CALENDAR_PRESENTATION"] = "empty"
        var records: [[String: Any]] = [
            ["id": taskID, "attributes": ["description": "Prepare the release with the product team", "status": "pending", "project": "Release", "scheduled": "1792231200", "due": "1792238400", "opaque": "retain"].map { ["key": $0.key, "value": $0.value] }],
            ["id": "A0000000-0000-0000-0000-000000000002", "attributes": [["key": "description", "value": "Review accessibility findings"], ["key": "status", "value": "pending"]]]
        ]
        if crowded {
            for index in 1...12 {
                records.append(["id": String(format: "90000000-0000-0000-0000-%012d", index), "attributes": [["key": "description", "value": "Earlier task \(index) with a longer title to fill the list"], ["key": "status", "value": "pending"]]])
            }
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
        let targets = app.buttons.matching(identifier: "task-row-outside").allElementsBoundByIndex.map { element in
            (element, element.frame.width * element.frame.height)
        }
        try XCTUnwrap(targets.max { $0.1 < $1.1 }).0.tap()
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Row editor " + name; shot.lifetime = .keepAlways; add(shot)
    }
}
