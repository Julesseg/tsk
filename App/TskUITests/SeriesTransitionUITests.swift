import XCTest
import UIKit

@MainActor
final class SeriesTransitionUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testExplicitSuccessorPreviewCancelCommitAndRetiredHistoryRemainSeparate() throws {
        let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "TaskwarriorRecurringFixture", withExtension: "json"))
        var records = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: source)) as? [[String: Any]])
        var oldID = "", overdueID = "", historyID = "", movedID = ""
        for index in records.indices {
            var attributes = try XCTUnwrap(records[index]["attributes"] as? [[String: String]])
            let id = try XCTUnwrap(records[index]["id"] as? String)
            if let mask = attributes.firstIndex(where: { $0["key"] == "mask" }) { oldID = id; attributes[mask]["value"] = "+-W" }
            else if attributes.contains(where: { $0["key"] == "imask" && $0["value"] == "0" }) {
                historyID = id
                let status = try XCTUnwrap(attributes.firstIndex { $0["key"] == "status" })
                attributes[status]["value"] = "completed"
                attributes.append(["key": "end", "value": "1792144700"])
            } else if attributes.contains(where: { $0["key"] == "imask" && $0["value"] == "1" }) {
                overdueID = id
                attributes.removeAll { ["due", "scheduled", "wait"].contains($0["key"] ?? "") }
                attributes.append(["key": "due", "value": "1792058400"])
            } else { movedID = id }
            records[index]["attributes"] = attributes
        }
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_NOW"] = "1792144800"
        app.launchEnvironment["TSK_TEST_RECORDED_RECURRENCE"] = String(decoding: try JSONSerialization.data(withJSONObject: records), as: UTF8.self)
        app.launch()
        openTemplates(app)
        let oldRow = app.buttons["recurring-template-" + oldID]
        XCTAssertTrue(oldRow.waitForExistence(timeout: 15))
        oldRow.tap()
        openEditor(app)
        editRule("0d", app: app)
        app.buttons["preview-series-transition"].tap()
        XCTAssertTrue(app.staticTexts["transition-error"].waitForExistence(timeout: 10))
        capture("Invalid transition cadence is rejected before a successor exists", app)
        editRule("monthly", app: app)
        app.buttons["preview-series-transition"].tap()
        assertPreview(movedID, app: app)
        capture("Preview explicitly retires old template and moves one existing future identity", app)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["edit-series-metadata"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["retired-template-explanation"].exists)
        openEditor(app)
        editRule("monthly", app: app)
        app.buttons["preview-series-transition"].tap()
        assertPreview(movedID, app: app)
        XCTAssertTrue(revealTaskElement(app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "transition-successor-")).firstMatch, in: "series-transition-form", app: app))
        let successorID = String(app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "transition-successor-")).firstMatch.identifier.dropFirst("transition-successor-".count))
        XCTAssertNotNil(UUID(uuidString: successorID))
        XCTAssertNotEqual(successorID, oldID)
        app.buttons["save-series-transition"].tap()
        XCTAssertTrue(app.staticTexts["retired-template-explanation"].waitForExistence(timeout: 15))
        XCTAssertTrue(revealTaskElement(app.buttons["view-transition-successor"], in: "task-detail-form", app: app))
        capture("Old template remains retired and separately links to the newly created template", app)
        XCTAssertTrue(revealTaskElement(app.buttons["view-series-occurrences"], in: "task-detail-form", app: app))
        app.buttons["view-series-occurrences"].tap()
        let overdue = app.buttons["series-history-" + overdueID]
        XCTAssertTrue(overdue.waitForExistence(timeout: 10))
        overdue.tap()
        XCTAssertTrue(revealTaskElement(app.buttons["complete-task"], in: "task-detail-form", app: app))
        app.buttons["complete-task"].tap()
        let completed = expectation(for: NSPredicate(format: "label CONTAINS %@", "Completed"), evaluatedWith: app.staticTexts["task-detail-status"])
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 10), .completed)
        capture("Excluded overdue occurrence still completes under its retired parent", app)
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "TSK_TEST_RECORDED_RECURRENCE")
        app.launch()
        selectAllTasks(app)
        XCTAssertTrue(app.buttons["task-" + movedID].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["task-" + overdueID].exists)
        openTemplates(app)
        XCTAssertTrue(app.buttons["recurring-template-" + successorID].waitForExistence(timeout: 15))
        XCTAssertTrue(revealTaskElement(oldRow, in: "recurring-template-list", app: app))
        oldRow.tap()
        XCTAssertTrue(app.staticTexts["retired-template-explanation"].waitForExistence(timeout: 10))
        XCTAssertTrue(revealTaskElement(app.buttons["view-series-occurrences"], in: "task-detail-form", app: app))
        app.buttons["view-series-occurrences"].tap()
        let history = app.buttons["series-history-" + historyID]
        XCTAssertTrue(history.waitForExistence(timeout: 10))
        history.tap()
        XCTAssertFalse(app.buttons["edit-task"].exists)
        XCTAssertFalse(app.buttons["complete-task"].exists)
        capture("Completed history remains reachable through the retired original identity", app)
    }

    private func openTemplates(_ app: XCUIApplication) {
        openWorkspaceSetting("recurring-templates", app: app)
        XCTAssertTrue(app.buttons["new-recurring-template"].waitForExistence(timeout: 10))
    }
    private func openEditor(_ app: XCUIApplication) {
        let button = app.buttons["transition-series"]
        XCTAssertTrue(revealTaskElement(button, in: "task-detail-form", app: app))
        button.tap()
        XCTAssertTrue(app.buttons["preview-series-transition"].waitForExistence(timeout: 10))
    }
    private func editRule(_ value: String, app: XCUIApplication) {
        let field = app.textFields["transition-rule"]
        XCTAssertTrue(revealTaskElement(field, in: "series-transition-form", app: app))
        replaceTaskText(field, with: value, app: app)
        if app.buttons["dismiss-transition-keyboard"].exists { tapTaskControlAtCenter(app.buttons["dismiss-transition-keyboard"], app: app) }
    }
    private func assertPreview(_ id: String, app: XCUIApplication) {
        XCTAssertTrue(app.buttons["save-series-transition"].waitForExistence(timeout: 10))
        let count = app.staticTexts["transition-preview-count"]
        XCTAssertTrue(revealTaskElement(count, in: "series-transition-form", app: app))
        XCTAssertEqual(count.label, "1 existing future task moves")
        XCTAssertTrue(revealTaskElement(app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "transition-successor-")).firstMatch, in: "series-transition-form", app: app))
        XCTAssertTrue(revealTaskElement(app.descendants(matching: .any)["transition-preview-" + id].firstMatch, in: "series-transition-form", app: app))
    }
    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
