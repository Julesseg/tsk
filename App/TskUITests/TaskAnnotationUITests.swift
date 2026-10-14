import UIKit
import XCTest

@MainActor
final class TaskAnnotationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testAddValidateEditAndReopenTimestampedAnnotations() throws {
        if UIDevice.current.userInterfaceIdiom == .pad { XCUIDevice.shared.orientation = .landscapeLeft }
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_NOW"] = "1792144800"
        app.launch()
        XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 10))
        app.buttons["new-task"].tap()
        let description = app.textFields["task-description"].exists ? app.textFields["task-description"] : app.textViews["task-description"]
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        description.typeText("Task with supporting notes")
        app.buttons["save-task"].tap()
        XCTAssertTrue(description.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Task with supporting notes"].firstMatch.waitForExistence(timeout: 10))
        app.staticTexts["Task with supporting notes"].firstMatch.tap()
        XCTAssertTrue(revealTaskElement(app.buttons["add-annotation"], in: "task-detail-form", app: app))
        capture("Annotations empty in native task detail", app: app)
        app.buttons["add-annotation"].tap()
        let editor = app.textViews["annotation-editor-text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        app.buttons["save-annotation"].tap()
        XCTAssertTrue(app.staticTexts["annotation-editor-error"].waitForExistence(timeout: 5))
        capture("Annotation validation remains visible after keyboard dismissal", app: app)
        editor.tap()
        editor.typeText("First supporting note\nAnother line")
        XCTAssertTrue(app.buttons["dismiss-annotation-keyboard"].waitForExistence(timeout: 5))
        app.buttons["dismiss-annotation-keyboard"].tap()
        capture("Multiline annotation review", app: app)
        app.buttons["save-annotation"].tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 10))
        XCTAssertTrue(revealTaskElement(app.staticTexts["annotation-text-annotation_1792144800"], in: "task-detail-form", app: app))
        XCTAssertEqual(app.staticTexts["annotation-text-annotation_1792144800"].label, "First supporting note\nAnother line")
        XCTAssertTrue(revealTaskElement(app.buttons["add-annotation"], in: "task-detail-form", app: app))
        app.buttons["add-annotation"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeText("Second independent note")
        app.typeKey("n", modifierFlags: .command)
        XCTAssertFalse(app.textFields["task-description"].exists)
        XCTAssertTrue(editor.exists)
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: .command)
        XCTAssertTrue(editor.waitForNonExistence(timeout: 10))
        XCTAssertTrue(revealTaskElement(app.buttons["edit-annotation_1792144800"], in: "task-detail-form", app: app))
        app.buttons["edit-annotation_1792144800"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeKey("a", modifierFlags: .command)
        editor.typeText("First supporting note\nAnother line revised")
        capture("Edit annotation keeps its original timestamp", app: app)
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: .command)
        XCTAssertTrue(editor.waitForNonExistence(timeout: 10))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Task with supporting notes"].firstMatch.waitForExistence(timeout: 10))
        app.staticTexts["Task with supporting notes"].firstMatch.tap()
        let first = app.staticTexts["annotation-text-annotation_1792144800"]
        let second = app.staticTexts["annotation-text-annotation_1792144801"]
        XCTAssertTrue(revealTaskElement(first, in: "task-detail-form", app: app))
        XCTAssertEqual(first.label, "First supporting note\nAnother line revised")
        XCTAssertTrue(revealTaskElement(second, in: "task-detail-form", app: app))
        XCTAssertEqual(second.label, "Second independent note")
        capture("Both annotations after durable reopen", app: app)
        XCTAssertTrue(revealTaskElement(app.staticTexts["task-detail-description"], in: "task-detail-form", app: app))
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
