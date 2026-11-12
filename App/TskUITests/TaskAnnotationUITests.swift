import UIKit
import XCTest

@MainActor
final class TaskAnnotationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testAddValidateEditAndReopenTimestampedAnnotations() throws {

        defer { XCUIDevice.shared.orientation = .portrait }
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_NOW"] = "1792144800"
        let commands = try TaskKeyboardCommand(.annotations, app: app)
        func save(_ phase: String) throws {
            try commands.perform(phase) { app.typeKey(XCUIKeyboardKey.return, modifierFlags: .command) }
        }
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 10))
        app.buttons["New task"].tap()
        let description = app.descendants(matching: .any).matching(identifier: "task-description").firstMatch
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        focusTaskText(description, app: app)
        description.typeText("Task with supporting notes")
        tapTaskControlAtCenter(app.buttons[taskEditorKeyboardDismissIdentifier(app)], app: app)
        XCTAssertEqual(description.value as? String, "Task with supporting notes")
        tapTaskControl(taskEditorSaveButton(app), app: app)
        XCTAssertTrue(waitForTaskSave(app, row: taskRow(named: "Task with supporting notes", app: app), timeout: 10))
        openTaskInformation(taskRow(named: "Task with supporting notes", app: app), app: app)
        XCTAssertTrue(revealTaskElement(app.buttons["add-annotation"], in: "task-detail-form", app: app))
        capture("Annotations empty in native task detail", app: app)
        app.buttons["add-annotation"].tap()
        let editor = app.descendants(matching: .any).matching(identifier: "annotation-editor-text").firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        app.buttons["save-annotation"].tap()
        XCTAssertTrue(app.staticTexts["annotation-editor-error"].waitForExistence(timeout: 5))
        capture("Annotation validation remains visible after keyboard dismissal", app: app)
        editor.tap()
        editor.typeText("First supporting note\nAnother line")
        XCTAssertTrue(app.buttons["dismiss-annotation-keyboard"].waitForExistence(timeout: 5))
        tapTaskControlAtCenter(app.buttons["dismiss-annotation-keyboard"], app: app)
        capture("Multiline annotation review", app: app)
        app.buttons["save-annotation"].tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 10))
        XCTAssertTrue(revealTaskElement(app.staticTexts["annotation-text-annotation_1792144800"], in: "task-detail-form", app: app))
        XCTAssertEqual(app.staticTexts["annotation-text-annotation_1792144800"].label, "First supporting note\nAnother line")
        XCTAssertTrue(revealTaskElement(app.buttons["add-annotation"], in: "task-detail-form", app: app))
        app.buttons["add-annotation"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("Second independent note")
        try commands.perform("secondNoteCommandN") { app.typeKey("n", modifierFlags: .command) }
        XCTAssertFalse(app.textFields["task-description"].exists)
        XCTAssertTrue(editor.exists)
        try save("secondNoteSave")
        XCTAssertTrue(editor.waitForNonExistence(timeout: 10))
        XCTAssertTrue(revealTaskElement(app.buttons["edit-annotation_1792144800"], in: "task-detail-form", app: app))
        app.buttons["edit-annotation_1792144800"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        try commands.perform("editSelectAll") { editor.typeKey("a", modifierFlags: .command) }
        editor.typeText("First supporting note\nAnother line revised")
        XCTAssertEqual(editor.value as? String, "First supporting note\nAnother line revised")
        capture("Edit annotation keeps its original timestamp", app: app)
        try save("editedNoteSave")
        XCTAssertTrue(editor.waitForNonExistence(timeout: 10))
        app.terminate()
        app.launch()
        selectAllTasks(app)
        XCTAssertTrue(taskRow(named: "Task with supporting notes", app: app).waitForExistence(timeout: 10))
        openTaskInformation(taskRow(named: "Task with supporting notes", app: app), app: app)
        let first = app.staticTexts["annotation-text-annotation_1792144800"]
        let second = app.staticTexts["annotation-text-annotation_1792144801"]
        XCTAssertTrue(revealTaskElement(first, in: "task-detail-form", app: app))
        XCTAssertEqual(first.label, "First supporting note\nAnother line revised")
        XCTAssertTrue(revealTaskElement(second, in: "task-detail-form", app: app))
        XCTAssertEqual(second.label, "Second independent note")
        capture("Both annotations after durable reopen", app: app)
        XCTAssertTrue(revealTaskElement(app.staticTexts["task-detail-description"], in: "task-detail-form", app: app, initialScrollUp: false))
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
