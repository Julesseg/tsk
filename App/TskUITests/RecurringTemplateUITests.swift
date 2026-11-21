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
        hideKeyboard("dismiss-recurring-keyboard", app: app)
        let rule = app.textFields["recurring-rule"]
        XCTAssertTrue(revealTaskElement(rule, in: "recurring-editor-form", app: app))
        rule.tap()
        rule.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20) + "0d")
        hideKeyboard("dismiss-recurring-keyboard", app: app)
        app.buttons["save-recurring-template"].tap()
        XCTAssertTrue(app.staticTexts["recurring-error"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["recurring-error"].label.contains("positive Taskwarrior recurrence"))
        capture("Nonprogressing recurrence is rejected", app)
        XCTAssertTrue(revealTaskElement(rule, in: "recurring-editor-form", app: app))
        rule.tap()
        rule.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20) + "weekly")
        hideKeyboard("dismiss-recurring-keyboard", app: app)
        app.buttons["save-recurring-template"].tap()
        XCTAssertTrue(waitForTaskSave(app, row: app.staticTexts["series-template-description"], timeout: 15, editorID: "recurring-editor-form"))
        XCTAssertEqual(app.staticTexts["series-template-description"].label, "Review recurring work")
        XCTAssertTrue(revealTaskElement(app.staticTexts["external-generation-explanation"], in: "series-template-form", app: app))
        XCTAssertTrue(app.buttons["edit-series-metadata"].exists)
        capture("Saved recurring template with explicit generator dependency", app)
        app.terminate()
        app.launch()
        selectAllTasks(app)
        XCTAssertTrue(app.staticTexts["No unfinished tasks"].waitForExistence(timeout: 10))
        XCTAssertFalse(taskRow(named: "Review recurring work", app: app).exists)
        openTemplates(app)
        XCTAssertTrue(app.staticTexts["Review recurring work"].waitForExistence(timeout: 10))
        app.staticTexts["Review recurring work"].tap()
        XCTAssertTrue(revealTaskElement(app.staticTexts["external-generation-explanation"], in: "series-template-form", app: app))
        capture("Recurring template persists without app-generated occurrences", app)
    }

    func testRecordedRealGeneratorOccurrenceEditsAndCompletesWithoutChangingItsTemplate() throws {
        let path = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "TaskwarriorRecurringFixture", withExtension: "json"))
        let data = try Data(contentsOf: path)
        try verifyRecordedOccurrenceEditingAndCompletion(data: data)
    }

    private func verifyRecordedOccurrenceEditingAndCompletion(data: Data) throws {
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
        selectAllTasks(app)
        let row = app.buttons["task-" + id]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["complete-task-row-" + id].exists)
        capture("Recorded occurrence offers its list completion circle", app)
        expandTaskRow(row, app: app)
        XCTAssertTrue(app.staticTexts["occurrence-only-explanation"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["This occurrence has an invalid template link or position."].exists)
        capture("Actual generator occurrence expands in its task view", app)
        let description = app.textFields["task-description"]
        XCTAssertTrue(description.waitForExistence(timeout: 10))
        let edited = try XCTUnwrap(description.value as? String) + " occurrence edit"
        replaceTaskText(description, with: edited, app: app)
        XCTAssertEqual(description.value as? String, edited)
        hideKeyboard("dismiss-row-keyboard", app: app)
        let supporting = app.scrollViews["task-row-editor"]
        XCTAssertTrue(revealTaskElement(app.buttons["occurrence-template"], in: supporting, app: app))
        app.buttons["occurrence-template"].tap()
        XCTAssertTrue(revealTaskElement(app.staticTexts["external-generation-explanation"], in: "series-template-form", app: app))
        capture("Recorded generated occurrence links to its distinct template", app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(description.waitForExistence(timeout: 10))
        closeTaskRow(app)
        XCTAssertTrue(waitForTaskSave(app, named: edited, timeout: 10))
        let complete = app.buttons["complete-task-row-" + id]
        XCTAssertTrue(complete.label.hasPrefix("Complete occurrence"))
        tapTaskControl(complete, app: app)
        XCTAssertTrue(complete.waitForNonExistence(timeout: 10))
        selectDoneTasks(app)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        capture("Occurrence completes while preserving series history", app)
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "TSK_TEST_RECORDED_RECURRENCE")
        app.launch()
        selectAllTasks(app)
        XCTAssertFalse(row.waitForExistence(timeout: 2))
        openTemplates(app)
        app.collectionViews["recurring-template-list"].buttons["recurring-template-" + parentID].tap()
        XCTAssertTrue(revealTaskElement(app.buttons["view-series-occurrences"], in: "series-template-form", app: app))
        app.buttons["view-series-occurrences"].tap()
        let history = app.buttons["series-history-" + id]
        XCTAssertTrue(history.waitForExistence(timeout: 10))
        history.tap()
        let completed = app.buttons["completed-task-row-" + id]
        XCTAssertTrue(completed.waitForExistence(timeout: 10))
        XCTAssertEqual(completed.value as? String, "Completed")
        let explanation = app.staticTexts["occurrence-only-explanation"]
        XCTAssertTrue(explanation.waitForExistence(timeout: 5))
        XCTAssertTrue(explanation.label.contains("completed occurrence"))
        XCTAssertFalse(app.descendants(matching: .any)["raw-attribute-mask"].firstMatch.exists)
        capture("Completed occurrence remains in reopened series history", app)
    }

    private func launch() -> XCUIApplication {
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_NOW"] = "1792144800"
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 15))
        return app
    }

    private func openTemplates(_ app: XCUIApplication) {
        openWorkspaceSetting("recurring-templates", app: app)
        XCTAssertTrue(app.buttons["new-recurring-template"].waitForExistence(timeout: 10))
    }

    private func hideKeyboard(_ identifier: String, app: XCUIApplication) {
        let hide = app.buttons[identifier]
        guard hide.exists else { return }
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists, app.frame.intersects(keyboard.frame), !keyboard.frame.isEmpty {
            tapTaskControlAtCenter(hide, app: app)
        } else {
            tapTaskControl(hide, app: app)
        }
        XCTAssertTrue(hide.waitForNonExistence(timeout: 5))
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
