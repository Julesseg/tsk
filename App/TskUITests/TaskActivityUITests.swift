import UIKit
import XCTest

@MainActor
final class TaskActivityUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testOrdinaryTaskListStartDetailStopPersistentReopenAndCompletionClearActiveState() throws {
        if UIDevice.current.userInterfaceIdiom == .pad { XCUIDevice.shared.orientation = .landscapeLeft }
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_NOW"] = "1792144800"
        app.launch()
        XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 20))
        app.buttons["new-task"].tap()
        let description = app.descendants(matching: .any).matching(identifier: "task-description").firstMatch
        XCTAssertTrue(description.waitForExistence(timeout: 5)); description.typeText("Act on independent plans")
        if app.buttons["dismiss-editor-keyboard"].exists { app.buttons["dismiss-editor-keyboard"].tap() }
        setDateSwitch("planned-day-enabled", to: true, app: app)
        setDateSwitch("deadline-enabled", to: true, app: app)
        app.buttons["save-task"].tap()
        let row = taskRow(named: "Act on independent plans", app: app)
        XCTAssertTrue(waitForTaskSave(app, row: row, timeout: 15))
        let id = String(row.identifier.dropFirst(5))
        row.press(forDuration: 1)
        XCTAssertTrue(app.buttons["start-task-" + id].waitForExistence(timeout: 5)); app.buttons["start-task-" + id].tap()
        waitForLabel("Active", on: taskRow(named: "Act on independent plans", app: app))
        capture("List context action starts work with a separate active caption", app)
        row.tap()
        XCTAssertTrue(revealTaskElement(app.buttons["stop-task"], in: "task-detail-form", app: app))
        let caption = app.descendants(matching: .any).matching(identifier: "task-activity-" + id).firstMatch
        XCTAssertTrue(caption.label.contains("Active"))
        app.buttons["stop-task"].tap()
        XCTAssertTrue(app.staticTexts["task-activity-inactive"].waitForExistence(timeout: 10))
        XCTAssertTrue(revealTaskElement(app.buttons["start-task"], in: "task-detail-form", app: app)); app.buttons["start-task"].tap()
        XCTAssertTrue(waitForEnabledTaskControl(app.buttons["stop-task"], app: app, timeout: 10))
        capture("Task detail distinguishes activity from planned day and deadline", app)
        app.terminate(); app.launch()
        XCTAssertTrue(taskRow(named: "Act on independent plans", app: app).waitForExistence(timeout: 15))
        waitForLabel("Active", on: taskRow(named: "Act on independent plans", app: app))
        taskRow(named: "Act on independent plans", app: app).tap()
        XCTAssertTrue(revealTaskElement(app.buttons["complete-task"], in: "task-detail-form", app: app)); app.buttons["complete-task"].tap()
        XCTAssertTrue(app.staticTexts["task-detail-status"].waitForExistence(timeout: 10))
        waitForLabel("Completed", on: app.staticTexts["task-detail-status"])
        XCTAssertFalse(app.buttons["start-task"].exists)
        XCTAssertFalse(app.buttons["stop-task"].exists)
        capture("Completion clears activity without offering accidental reopen", app)
    }

    func testRecordedRealOccurrenceStartsStopsAndCompletesThroughItsSeries() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "TaskwarriorRecurringFixture", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let records = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let child = try XCTUnwrap(records.first { ($0["attributes"] as? [[String: String]] ?? []).contains { $0["key"] == "parent" } })
        let id = try XCTUnwrap(child["id"] as? String)
        let app = XCUIApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_NOW"] = "1792144800"
        app.launchEnvironment["TSK_TEST_RECORDED_RECURRENCE"] = String(decoding: data, as: UTF8.self)
        app.launch()
        let row = app.buttons["task-" + id]
        XCTAssertTrue(row.waitForExistence(timeout: 20)); row.tap()
        XCTAssertTrue(revealTaskElement(app.buttons["start-task"], in: "task-detail-form", app: app)); app.buttons["start-task"].tap()
        XCTAssertTrue(waitForEnabledTaskControl(app.buttons["stop-task"], app: app, timeout: 10))
        capture("Recorded generated occurrence supports active work independently of waiting", app)
        app.buttons["stop-task"].tap()
        XCTAssertTrue(waitForEnabledTaskControl(app.buttons["start-task"], app: app, timeout: 10)); app.buttons["start-task"].tap()
        XCTAssertTrue(revealTaskElement(app.buttons["complete-task"], in: "task-detail-form", app: app)); app.buttons["complete-task"].tap()
        waitForLabel("Completed", on: app.staticTexts["task-detail-status"])
        XCTAssertFalse(app.buttons["stop-task"].exists)
        XCTAssertFalse(app.buttons["start-task"].exists)
        capture("Occurrence completion removes its active marker", app)
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "TSK_TEST_RECORDED_RECURRENCE")
        app.launch()
        XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 15))
        XCTAssertFalse(row.exists)
    }

    func testInvalidOccurrenceStartShowsVisibleFailureAndKeepsSavedTaskUnchanged() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "TaskwarriorRecurringFixture", withExtension: "json"))
        var records = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        let parentIndex = try XCTUnwrap(records.firstIndex { ($0["attributes"] as? [[String: String]] ?? []).contains { $0["key"] == "mask" } })
        var attributes = try XCTUnwrap(records[parentIndex]["attributes"] as? [[String: String]])
        let maskIndex = try XCTUnwrap(attributes.firstIndex { $0["key"] == "mask" })
        attributes[maskIndex]["value"] = "?WW"; records[parentIndex]["attributes"] = attributes
        let child = try XCTUnwrap(records.first { ($0["attributes"] as? [[String: String]] ?? []).contains { $0["key"] == "parent" } })
        let id = try XCTUnwrap(child["id"] as? String)
        let app = XCUIApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_RECORDED_RECURRENCE"] = String(decoding: try JSONSerialization.data(withJSONObject: records), as: UTF8.self)
        app.launch()
        XCTAssertTrue(app.buttons["task-" + id].waitForExistence(timeout: 20)); app.buttons["task-" + id].tap()
        XCTAssertTrue(revealTaskElement(app.buttons["start-task"], in: "task-detail-form", app: app)); app.buttons["start-task"].tap()
        XCTAssertTrue(app.staticTexts["task-action-banner"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["task-action-banner"].label.contains("No tasks were changed"))
        XCTAssertFalse(app.buttons["stop-task"].exists)
        capture("Invalid recurrence state reports a visible genuine start failure", app)
    }

    private func waitForLabel(_ text: String, on element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed)
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
