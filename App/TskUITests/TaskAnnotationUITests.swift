import UIKit
import XCTest

@MainActor
final class TaskAnnotationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testAddValidateEditAndReopenTimestampedAnnotations() throws {
        try exerciseAnnotationRoundTrip()
    }

    func testToolbarSaveValidatesEditsAndDurablyReopensTimestampedAnnotations() throws {
        try exerciseAnnotationRoundTrip(keyboardShortcuts: false)
    }

    private func exerciseAnnotationRoundTrip(keyboardShortcuts: Bool = true) throws {
        if UIDevice.current.userInterfaceIdiom == .pad { XCUIDevice.shared.orientation = .landscapeLeft }
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_NOW"] = "1792144800"
        let commands = keyboardShortcuts ? try TaskKeyboardCommand(.annotations, app: app) : nil
        func save(_ phase: String) throws {
            if let commands {
                try commands.perform(phase) { app.typeKey(XCUIKeyboardKey.return, modifierFlags: .command) }
            } else { tapTaskControlAtCenter(app.buttons["save-annotation"], app: app) }
        }
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 10))
        app.buttons["New task"].tap()
        let description = app.textFields["task-description"].exists ? app.textFields["task-description"] : app.textViews["task-description"]
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        focusTaskText(description, app: app)
        description.typeText("Task with supporting notes")
        tapTaskControlAtCenter(app.buttons["dismiss-editor-keyboard"], app: app)
        XCTAssertEqual(description.value as? String, "Task with supporting notes")
        tapTaskControl(app.buttons["save-task"], app: app)
        XCTAssertTrue(waitForTaskSave(app, row: taskRow(named: "Task with supporting notes", app: app), timeout: 10))
        taskRow(named: "Task with supporting notes", app: app).tap()
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
        if let commands {
            try commands.perform("secondNoteCommandN") { app.typeKey("n", modifierFlags: .command) }
            XCTAssertFalse(app.textFields["task-description"].exists)
            XCTAssertTrue(editor.exists)
        }
        try save("secondNoteSave")
        XCTAssertTrue(editor.waitForNonExistence(timeout: 10))
        XCTAssertTrue(revealTaskElement(app.buttons["edit-annotation_1792144800"], in: "task-detail-form", app: app))
        app.buttons["edit-annotation_1792144800"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        if let commands {
            try commands.perform("editSelectAll") { editor.typeKey("a", modifierFlags: .command) }
        } else {
            let original = try XCTUnwrap(editor.value as? String)
            XCTAssertEqual(original, "First supporting note\nAnother line")
            editor.press(forDuration: 1.1)
            let menu = app.menuItems["Select All"]
            let button = app.buttons["Select All"]
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in menu.exists || button.exists }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
            let selectAll = menu.exists ? menu : button
            selectAll.tap()
        }
        editor.typeText("First supporting note\nAnother line revised")
        if !keyboardShortcuts { XCTAssertEqual(editor.value as? String, "First supporting note\nAnother line revised") }
        capture("Edit annotation keeps its original timestamp", app: app)
        try save("editedNoteSave")
        XCTAssertTrue(editor.waitForNonExistence(timeout: 10))
        app.terminate()
        app.launch()
        selectAllTasks(app)
        XCTAssertTrue(taskRow(named: "Task with supporting notes", app: app).waitForExistence(timeout: 10))
        taskRow(named: "Task with supporting notes", app: app).tap()
        let first = app.staticTexts["annotation-text-annotation_1792144800"]
        let second = app.staticTexts["annotation-text-annotation_1792144801"]
        XCTAssertTrue(revealTaskElement(first, in: "task-detail-form", app: app))
        XCTAssertEqual(first.label, "First supporting note\nAnother line revised")
        XCTAssertTrue(revealTaskElement(second, in: "task-detail-form", app: app))
        XCTAssertEqual(second.label, "Second independent note")
        capture("Both annotations after durable reopen", app: app)
        XCTAssertTrue(revealTaskElement(app.staticTexts["task-detail-description"], in: "task-detail-form", app: app, initialScrollUp: false))
    }

    func testIndependentNativeTextViewRecognizesPlainAndCommandKeys() throws {
        struct State: Codable {
            let processID: Int32
            let firstResponder: Bool
            let textLength: Int
            let textIsPlainN: Bool
            let commandNCount: Int
            let commandReturnCount: Int
        }
        XCTAssertEqual(ProcessInfo.processInfo.environment["TSK_UI_ISOLATED_SIMULATOR"], "1")
        let app = taskTestApplication(), token = UUID().uuidString
        addTeardownBlock { app.terminate() }
        app.launchEnvironment["TSK_UI_ISOLATED_SIMULATOR"] = "1"
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = token
        app.launchEnvironment["TSK_TEST_NATIVE_KEYBOARD_CONTROL"] = token
        func state() -> State? {
            guard let application = try? app.snapshot(),
                  let snapshot = taskSnapshot("native-keyboard-control-status", type: .staticText, in: application),
                  let raw = snapshot.value as? String, raw.utf8.count <= 1024 else { return nil }
            return try? JSONDecoder().decode(State.self, from: Data(raw.utf8))
        }
        enum Phase: String, Encodable { case startup, plain, commandN, commandReturn, teardown }
        struct Observation: Encodable { let phase: Phase; let state: State? }
        func retain(_ phase: Phase) {
            guard let data = try? JSONEncoder().encode(Observation(phase: phase, state: state())), data.count <= 1024 else { return }
            let raw = String(decoding: data, as: UTF8.self)
            print("TSK_NATIVE_KEYBOARD_CONTROL_V1 " + raw)
            let attachment = XCTAttachment(string: raw)
            attachment.name = "Independent native keyboard control \(phase.rawValue) typed state"; attachment.lifetime = .keepAlways; add(attachment)
        }
        addTeardownBlock { retain(.teardown) }
        app.launch()
        let input = app.textViews["native-keyboard-control-input"]
        let inputExists = input.waitForExistence(timeout: 20)
        retain(.startup)
        XCTAssertTrue(inputExists)
        input.tap()
        app.typeKey("n", modifierFlags: [])
        let plain = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let state = state() else { return false }
            return state.firstResponder && state.textIsPlainN
        }, object: nil)
        let plainResult = XCTWaiter.wait(for: [plain], timeout: 10)
        retain(.plain)
        XCTAssertEqual(plainResult, .completed)
        XCTAssertEqual(input.value as? String, "n")
        app.typeKey("n", modifierFlags: .command)
        let commandN = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in state()?.commandNCount == 1 }, object: nil)
        let commandNResult = XCTWaiter.wait(for: [commandN], timeout: 10)
        retain(.commandN)
        XCTAssertEqual(commandNResult, .completed)
        XCTAssertEqual(input.value as? String, "n")
        let commands = try TaskKeyboardCommand(.native, app: app)
        let nativeState = state().map { TaskKeyboardRequest.NativeState(processID: $0.processID, firstResponder: $0.firstResponder, textLength: $0.textLength, textIsPlainN: $0.textIsPlainN, commandNCount: $0.commandNCount, commandReturnCount: $0.commandReturnCount) }
        try commands.perform("commandReturn", nativeState: nativeState) { app.typeKey(XCUIKeyboardKey.return, modifierFlags: .command) }
        let commandReturn = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in state()?.commandReturnCount == 1 }, object: nil)
        let commandReturnResult = XCTWaiter.wait(for: [commandReturn], timeout: 10)
        retain(.commandReturn)
        XCTAssertEqual(commandReturnResult, .completed)
        XCTAssertEqual(input.value as? String, "n")
        capture("Independent native UITextView consumes actual Command keys without inserting text", app: app)
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
