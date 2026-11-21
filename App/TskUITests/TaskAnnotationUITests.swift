import XCTest

@MainActor
final class TaskAnnotationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testAddValidateEditAndReopenTimestampedAnnotations() async throws {
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_NOW"] = "1792144800"
        app.launch()
        let name = "Task with supporting notes"
        tapTaskControl(app.buttons["new-task"], app: app)
        let title = app.textFields["task-description"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        focusTaskText(title, app: app)
        title.typeText(name)
        hideKeyboard(app)
        closeTaskRow(app)
        XCTAssertTrue(waitForTaskSave(app, named: name, timeout: 10))

        let row = taskRow(named: name, app: app)
        expandTaskRow(row, app: app)
        let note = app.descendants(matching: .any)["row-note-input"].firstMatch
        let first = app.descendants(matching: .any)["row-note-annotation_1792144800"].firstMatch
        XCTAssertFalse(first.exists)
        focusTaskText(note, app: app)
        note.typeText("First supporting note\nAnother line")
        hideKeyboard(app)
        closeTaskRow(app)
        XCTAssertTrue(waitForTaskSave(app, named: name, timeout: 10))

        expandTaskRow(row, app: app)
        XCTAssertEqual(first.value as? String, "First supporting note\nAnother line")
        let revised = "First supporting note\nAnother line revised"
        replaceTaskText(first, with: revised, app: app)
        focusTaskText(note, app: app)
        note.typeText("Second independent note")
        hideKeyboard(app)
        closeTaskRow(app)
        XCTAssertTrue(waitForTaskSave(app, named: name, timeout: 10))

        app.terminate()
        app.launch()
        expandTaskRow(row, app: app)
        XCTAssertEqual(first.value as? String, revised)
        XCTAssertEqual(app.descendants(matching: .any)["row-note-annotation_1792144801"].firstMatch.value as? String, "Second independent note")
        app.terminate()
        let saved = try await storedTasks(app, checkpoint: "saved")
        XCTAssertEqual(saved.count, 1)
        let attributes = try XCTUnwrap(saved.values.first)
        XCTAssertEqual(attributes["description"], name)
        XCTAssertEqual(attributes["annotation_1792144800"], revised)
        XCTAssertEqual(attributes["annotation_1792144801"], "Second independent note")
        XCTAssertEqual(attributes.keys.filter { $0.hasPrefix("annotation_") }.count, 2)
    }

    private func hideKeyboard(_ app: XCUIApplication) {
        tapTaskControlAtCenter(app.buttons["dismiss-row-keyboard"], app: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
    }
}
