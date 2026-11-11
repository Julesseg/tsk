import UIKit
import XCTest

@MainActor
final class TaskActivityUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testOrdinaryTaskInformationStartStopPersistentReopenAndCompletionClearActiveState() throws {
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_NOW"] = "1792144800"
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20))
        app.buttons["New task"].tap()
        let description = app.descendants(matching: .any).matching(identifier: "task-description").firstMatch
        XCTAssertTrue(description.waitForExistence(timeout: 5)); description.typeText("Act on independent plans")
        if app.buttons[taskEditorKeyboardDismissIdentifier(app)].exists { tapTaskControlAtCenter(app.buttons[taskEditorKeyboardDismissIdentifier(app)], app: app) }
        setDateSwitch("planned-day-enabled", to: true, app: app)
        setDateSwitch("deadline-enabled", to: true, app: app)
        taskEditorSaveButton(app).tap()
        let row = taskRow(named: "Act on independent plans", app: app)
        XCTAssertTrue(waitForTaskSave(app, row: row, timeout: 15))
        let id = String(row.identifier.dropFirst(5))
        openTaskInformation(row, app: app)
        XCTAssertTrue(revealTaskElement(app.buttons["start-task"], in: "task-detail-form", app: app))
        app.buttons["start-task"].tap()
        XCTAssertTrue(revealTaskElement(app.buttons["stop-task"], in: "task-detail-form", app: app))
        let caption = app.descendants(matching: .any).matching(identifier: "task-activity-" + id).firstMatch
        XCTAssertTrue(caption.label.contains("Active"))
        app.buttons["stop-task"].tap()
        XCTAssertTrue(app.staticTexts["task-activity-inactive"].waitForExistence(timeout: 10))
        XCTAssertTrue(revealTaskElement(app.buttons["start-task"], in: "task-detail-form", app: app)); app.buttons["start-task"].tap()
        XCTAssertTrue(waitForEnabledTaskControl(app.buttons["stop-task"], app: app, timeout: 10))
        capture("Task detail distinguishes activity from planned day and deadline", app)
        app.terminate(); app.launch()
        selectAllTasks(app)
        XCTAssertTrue(taskRow(named: "Act on independent plans", app: app).waitForExistence(timeout: 15))
        XCTAssertFalse(taskRow(named: "Act on independent plans", app: app).label.contains("Active"))
        openTaskInformation(taskRow(named: "Act on independent plans", app: app), app: app)
        XCTAssertTrue(revealTaskElement(caption, in: "task-detail-form", app: app))
        waitForLabel("Active", on: caption)
        XCTAssertTrue(revealTaskElement(app.buttons["complete-task"], in: "task-detail-form", app: app)); app.buttons["complete-task"].tap()
        XCTAssertTrue(app.staticTexts["task-detail-status"].waitForExistence(timeout: 10))
        waitForLabel("Completed", on: app.staticTexts["task-detail-status"])
        XCTAssertFalse(app.buttons["start-task"].exists)
        XCTAssertFalse(app.buttons["stop-task"].exists)
        capture("Completion clears activity without offering accidental reopen", app)
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
