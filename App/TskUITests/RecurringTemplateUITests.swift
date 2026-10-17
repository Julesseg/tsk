import XCTest

@MainActor
final class RecurringTemplateUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testRecurringTemplateValidationCreationInspectionAndPersistentReopen() {
        let app = launch()
        openTemplates(app)
        XCTAssertTrue(app.staticTexts["No recurring templates"].waitForExistence(timeout: 10))
        capture("Recurring templates waiting for external generation", app)
        app.buttons["new-recurring-template"].tap()
        XCTAssertTrue(app.buttons["save-recurring-template"].waitForExistence(timeout: 5))
        app.buttons["save-recurring-template"].tap()
        XCTAssertTrue(app.staticTexts["recurring-error"].waitForExistence(timeout: 5))
        capture("Recurring template requires a description", app)
        let description = app.textFields["recurring-description"].exists ? app.textFields["recurring-description"] : app.textViews["recurring-description"]
        XCTAssertTrue(revealTaskElement(description, in: "recurring-editor-form", app: app))
        description.tap()
        description.typeText("Review recurring work")
        hideKeyboard(app)
        let rule = app.textFields["recurring-rule"]
        XCTAssertTrue(revealTaskElement(rule, in: "recurring-editor-form", app: app))
        rule.tap()
        rule.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20) + "0d")
        hideKeyboard(app)
        app.buttons["save-recurring-template"].tap()
        XCTAssertTrue(app.staticTexts["recurring-error"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["recurring-error"].label.contains("positive Taskwarrior recurrence"))
        capture("Nonprogressing recurrence is rejected", app)
        XCTAssertTrue(revealTaskElement(rule, in: "recurring-editor-form", app: app))
        rule.tap()
        rule.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20) + "weekly")
        hideKeyboard(app)
        app.buttons["save-recurring-template"].tap()
        XCTAssertTrue(waitForTaskSave(app, row: app.staticTexts["task-detail-description"], timeout: 15, editorID: "recurring-editor-form"))
        XCTAssertEqual(app.staticTexts["task-detail-description"].label, "Review recurring work")
        XCTAssertTrue(revealTaskElement(app.staticTexts["external-generation-explanation"], in: "task-detail-form", app: app))
        XCTAssertFalse(app.buttons["complete-task"].exists)
        XCTAssertFalse(app.buttons["edit-task"].exists)
        capture("Saved recurring template with explicit generator dependency", app)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["No unfinished tasks"].waitForExistence(timeout: 10))
        openTemplates(app)
        XCTAssertTrue(app.staticTexts["Review recurring work"].waitForExistence(timeout: 10))
        app.staticTexts["Review recurring work"].tap()
        XCTAssertTrue(revealTaskElement(app.staticTexts["external-generation-explanation"], in: "task-detail-form", app: app))
        capture("Recurring template persists without app-generated occurrences", app)
    }

    func testRecordedRealGeneratorOccurrenceEditsAndCompletesWithoutChangingItsTemplate() throws {
        let path = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "TaskwarriorRecurringFixture", withExtension: "json"))
        let data = try Data(contentsOf: path)
        let records = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let child = try XCTUnwrap(records.first { record in
            let attributes = record["attributes"] as? [[String: String]] ?? []
            return attributes.contains { $0["key"] == "parent" }
        })
        let id = try XCTUnwrap(child["id"] as? String)
        let rawParentID = try XCTUnwrap((child["attributes"] as? [[String: String]])?.first { $0["key"] == "parent" }?["value"])
        let parentID = try XCTUnwrap(UUID(uuidString: rawParentID), "The recorded occurrence must reference a valid template UUID").uuidString
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_NOW"] = "1792144800"
        app.launchEnvironment["TSK_TEST_RECORDED_RECURRENCE"] = String(decoding: data, as: UTF8.self)
        app.launch()
        let row = app.buttons["task-" + id]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.tap()
        XCTAssertTrue(app.staticTexts["occurrence-only-explanation"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["edit-task"].label, "Edit occurrence")
        capture("Actual generator occurrence offers occurrence-only actions", app)
        app.buttons["edit-task"].tap()
        let description = app.textViews["task-description"].exists ? app.textViews["task-description"] : app.textFields["task-description"]
        XCTAssertTrue(description.waitForExistence(timeout: 10))
        description.tap()
        description.typeText(" occurrence edit")
        if app.buttons["dismiss-editor-keyboard"].exists { app.buttons["dismiss-editor-keyboard"].tap() }
        app.buttons["save-task"].tap()
        XCTAssertTrue(waitForTaskSave(app, row: app.staticTexts["task-detail-description"], timeout: 10))
        XCTAssertTrue(app.staticTexts["task-detail-description"].label.contains("occurrence edit"))
        XCTAssertTrue(revealTaskElement(app.buttons["complete-task"], in: "task-detail-form", app: app))
        XCTAssertEqual(app.buttons["complete-task"].label, "Complete occurrence")
        app.buttons["complete-task"].tap()
        XCTAssertTrue(app.staticTexts["task-detail-status"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["task-detail-status"].label.contains("Completed"))
        XCTAssertFalse(app.buttons["edit-task"].exists)
        capture("Occurrence completes while preserving series history", app)
        XCTAssertTrue(revealTaskElement(app.buttons["occurrence-template"], in: "task-detail-form", app: app))
        app.buttons["occurrence-template"].tap()
        XCTAssertTrue(revealTaskElement(app.staticTexts["external-generation-explanation"], in: "task-detail-form", app: app))
        capture("Recorded generated occurrence links to its distinct template", app)
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "TSK_TEST_RECORDED_RECURRENCE")
        app.launch()
        XCTAssertFalse(row.waitForExistence(timeout: 2))
        openTemplates(app)
        app.collectionViews["recurring-template-list"].buttons["recurring-template-" + parentID].tap()
        XCTAssertTrue(revealTaskElement(app.otherElements["raw-attribute-mask"], in: "task-detail-form", app: app) || revealTaskElement(app.staticTexts["raw-attribute-mask"], in: "task-detail-form", app: app))
        let mask = app.descendants(matching: .any)["raw-attribute-mask"].firstMatch
        XCTAssertEqual(mask.value as? String, "WW+")
        capture("Occurrence completion mask persists after reopening shared storage", app)
    }

    func testMalformedSeriesMaskExposesAnErrorAndKeepsTheOccurrencePending() throws {
        let path = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "TaskwarriorRecurringFixture", withExtension: "json"))
        var records = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [[String: Any]])
        let parentIndex = try XCTUnwrap(records.firstIndex { record in (record["attributes"] as? [[String: String]] ?? []).contains { $0["key"] == "mask" } })
        var attributes = try XCTUnwrap(records[parentIndex]["attributes"] as? [[String: String]])
        let maskIndex = try XCTUnwrap(attributes.firstIndex { $0["key"] == "mask" })
        attributes[maskIndex]["value"] = "?WW"
        records[parentIndex]["attributes"] = attributes
        let child = try XCTUnwrap(records.first { record in (record["attributes"] as? [[String: String]] ?? []).contains { $0["key"] == "parent" } })
        let id = try XCTUnwrap(child["id"] as? String)
        let parentID = try XCTUnwrap((child["attributes"] as? [[String: String]])?.first { $0["key"] == "parent" }?["value"])
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_RECORDED_RECURRENCE"] = String(decoding: try JSONSerialization.data(withJSONObject: records), as: UTF8.self)
        app.launch()
        let row = app.buttons["task-" + id]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.tap()
        XCTAssertTrue(revealTaskElement(app.buttons["complete-task"], in: "task-detail-form", app: app))
        app.buttons["complete-task"].tap()
        XCTAssertTrue(revealTaskElement(app.staticTexts["task-action-error"], in: "task-detail-form", app: app))
        XCTAssertTrue(app.staticTexts["task-action-error"].label.contains("No tasks were changed"))
        capture("Malformed series mask prevents completion without discarding the occurrence", app)
        XCTAssertTrue(revealTaskElement(app.buttons["complete-task"], in: "task-detail-form", app: app, initialScrollUp: false))
        XCTAssertTrue(app.buttons["complete-task"].exists)
    }

    private func launch() -> XCUIApplication {
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_NOW"] = "1792144800"
        app.launch()
        XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 15))
        return app
    }

    private func openTemplates(_ app: XCUIApplication) {
        let button = app.buttons["recurring-templates"]
        if !button.isHittable { XCTAssertTrue(revealTaskElement(button, in: "workspace-sidebar", app: app)) }
        button.tap()
        XCTAssertTrue(app.buttons["new-recurring-template"].waitForExistence(timeout: 10))
    }

    private func hideKeyboard(_ app: XCUIApplication) {
        let hide = app.buttons["dismiss-recurring-keyboard"]
        if hide.exists { hide.tap() }
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
