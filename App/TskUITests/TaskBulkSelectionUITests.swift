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

    func testContinuousSelectionFreezesRowsBeforeReleaseAndCompletesDurably() throws {
        let app = try launch(probe: true)
        let list = app.collectionViews["task-list"]
        let initial = app.buttons["task-" + first].frame
        let last = app.buttons["task-" + third].frame
        let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: list.frame.minX + 60, dy: initial.midY))
        let end = start.withOffset(CGVector(dx: list.frame.width * 0.7, dy: last.midY - initial.midY))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: list.frame.width * 0.15, dy: 0)))
        XCTAssertFalse(app.staticTexts["task-selection-count"].exists)
        XCTAssertFalse(app.textFields["task-description"].exists, "A short swipe must not open the editor")
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 2)
        let count = app.staticTexts["task-selection-count"]
        XCTAssertTrue(count.waitForExistence(timeout: 10))
        XCTAssertEqual(count.label, "3 selected")
        let data = try XCTUnwrap((count.value as? String)?.data(using: .utf8))
        let proof = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(proof["selectedWhileTouchDown"] as? Bool, true)
        XCTAssertEqual(proof["maximumSelectedWhileTouchDown"] as? Int, 3)
        XCTAssertEqual(proof["scrollingDisabled"] as? Bool, true)
        XCTAssertEqual(proof["offsetsStable"] as? Bool, true)
        XCTAssertEqual(proof["rowsStable"] as? Bool, true)
        XCTAssertEqual(proof["refreshWhileTouchDown"] as? Bool, true)
        XCTAssertGreaterThan(try XCTUnwrap(proof["maximumRowTranslation"] as? Double), 8, "The touched row follows the finger horizontally")
        let width = try XCTUnwrap(proof["columnWidth"] as? Double)
        let crossing = try XCTUnwrap(proof["crossingDistance"] as? Double)
        XCTAssertEqual(width, list.frame.width, accuracy: 2)
        if UIDevice.current.userInterfaceIdiom == .pad { XCTAssertLessThan(width, app.frame.width * 0.75) }
        XCTAssertGreaterThanOrEqual(crossing, width * 0.25)
        XCTAssertLessThan(crossing, width * 0.45)
        XCTAssertTrue(taskRow(named: "Arrived while selecting", app: app).waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["task-" + first].frame.minX, initial.minX, accuracy: 1, "Rows settle back after release")
        let reverseStart = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: list.frame.minX + 60, dy: app.buttons["task-" + third].frame.midY))
        reverseStart.press(forDuration: 0.05, thenDragTo: reverseStart.withOffset(CGVector(dx: list.frame.width * 0.5, dy: app.buttons["task-" + first].frame.midY - app.buttons["task-" + third].frame.midY)))
        XCTAssertEqual(count.label, "3 selected", "Repeated contact adds without toggling")
        let circles = app.buttons.matching(identifier: "complete-task-row-" + second)
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
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: list.frame.width * 0.4, dy: 0)))
        let count = app.staticTexts["task-selection-count"]
        XCTAssertTrue(count.waitForExistence(timeout: 10))
        XCTAssertEqual(count.label, "1 selected")
        let circles = app.buttons.matching(identifier: "complete-task-row-" + first)
        XCTAssertEqual(circles.count, 2)
        for circle in circles.allElementsBoundByIndex { XCTAssertEqual(circle.value as? String, "Selected") }
        circles.element(boundBy: 1).tap()
        XCTAssertEqual(count.label, "0 selected")
        circles.element(boundBy: 0).tap()
        app.buttons["complete-task-selection"].tap()
        XCTAssertTrue(app.staticTexts["task-selection-error"].waitForExistence(timeout: 10))
        XCTAssertEqual(count.label, "1 selected")
        XCTAssertTrue(planned.exists)
        app.buttons["task-selection-done"].tap()
        XCTAssertTrue(count.waitForNonExistence(timeout: 5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: list.frame.width * 0.4, dy: 0)))
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
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: list.frame.width * (continuingVertically ? 0.7 : 0.4), dy: continuingVertically ? 104 : 0)), withVelocity: .slow, thenHoldForDuration: 1)
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
        quickStart.press(forDuration: 0.05, thenDragTo: quickStart.withOffset(CGVector(dx: list.frame.width * 0.4, dy: 0)), withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertTrue(title.waitForNonExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["task-selection-count"].label, "1 selected")
        let row = app.buttons["task-" + first]
        let beforeScroll = row.frame.minY
        list.swipeUp()
        XCTAssertTrue(!row.exists || abs(row.frame.minY - beforeScroll) > 1, "An editor save finishing after release must restore scrolling")
        XCTAssertEqual(app.staticTexts["task-selection-count"].label, "1 selected")
        app.buttons["task-selection-done"].tap()
    }

    private func launch(probe: Bool = false, invalidOccurrence: Bool = false, crowded: Bool = false) throws -> XCUIApplication {
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_NOW"] = "1792144800"
        app.launchEnvironment["TSK_TEST_CALENDAR_PRESENTATION"] = "empty"
        if probe {
            app.launchEnvironment["TSK_TEST_SELECTION_GESTURE"] = "1"
            app.launchEnvironment["TSK_UI_DISABLE_ANIMATIONS"] = "0"
        }
        if crowded { app.launchEnvironment["TSK_TEST_SELECTION_EDITOR_DELAY"] = "1" }
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
