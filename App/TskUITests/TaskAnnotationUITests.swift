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
        tapTaskControlAtCenter(app.buttons["dismiss-annotation-keyboard"], app: app)
        tapTaskControl(app.buttons["save-annotation"], app: app)
        XCTAssertTrue(editor.waitForNonExistence(timeout: 10))
        XCTAssertTrue(revealTaskElement(app.buttons["edit-annotation_1792144800"], in: "task-detail-form", app: app))
        app.buttons["edit-annotation_1792144800"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        replaceTaskText(editor, with: "First supporting note\nAnother line revised", app: app)
        XCTAssertEqual(editor.value as? String, "First supporting note\nAnother line revised")
        capture("Edit annotation keeps its original timestamp", app: app)
        tapTaskControlAtCenter(app.buttons["dismiss-annotation-keyboard"], app: app)
        tapTaskControl(app.buttons["save-annotation"], app: app)
        XCTAssertTrue(editor.waitForNonExistence(timeout: 10))
        app.terminate()
        let saved = try storedTasks(app, checkpoint: "saved")
        XCTAssertEqual(saved.count, 1)
        let attributes = try XCTUnwrap(saved.values.first)
        XCTAssertEqual(attributes["description"], "Task with supporting notes")
        XCTAssertEqual(attributes["annotation_1792144800"], "First supporting note\nAnother line revised")
        XCTAssertEqual(attributes["annotation_1792144801"], "Second independent note")
        XCTAssertEqual(attributes.keys.filter { $0.hasPrefix("annotation_") }.count, 2)

    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
