import UIKit
import XCTest

@MainActor final class TaskKeyboardCompatibilityUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        XCUIApplication().terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testWorkspaceAndEditorCommandsKeepOwnershipAcrossFocus() throws {
        guard try TaskKeyboardSession.usesHID(environment: ProcessInfo.processInfo.environment) else {
            XCTFail("Product command compatibility requires the owned native HID transport")
            return
        }
        let app = taskTestApplication()
        app.launchArguments += ["-AppleLocale", "en_US", "-AppleLanguages", "(en)"]
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_NOW"] = "1792144800"
        app.launchEnvironment["TSK_UI_ISOLATED_SIMULATOR"] = "1"
        app.launch()
        selectDoneTasks(app)
        selectAllTasks(app)
        let commands = try TaskKeyboardCommand(.workspaceCompatibility, app: app)
        func command(_ phase: String) throws {
            try commands.perform(phase) { XCTFail("An owned HID command cannot fall back to an app action") }
        }
        let field = app.textFields["task-description"]
        XCTAssertFalse(field.exists)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        try command("capture")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        focusTaskText(field, app: app)
        field.typeText("Keyboard ownership n")
        XCTAssertEqual(field.value as? String, "Keyboard ownership n")
        XCTAssertEqual(app.textFields.matching(identifier: "task-description").count, 1)
        try command("saveNew")
        XCTAssertTrue(field.waitForNonExistence(timeout: 10))
        let original = taskRow(named: "Keyboard ownership n", app: app)
        XCTAssertTrue(original.waitForExistence(timeout: 10))
        let identity = original.identifier
        try command("select")
        XCTAssertTrue(original.exists)
        try command("edit")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "Keyboard ownership n")
        focusTaskText(field, app: app)
        field.typeText(" revised n")
        let editedDraft = try XCTUnwrap(field.value as? String)
        XCTAssertEqual(editedDraft.components(separatedBy: " revised n").count, 2)
        XCTAssertEqual(editedDraft.replacingOccurrences(of: " revised n", with: ""), "Keyboard ownership n")
        let revised = editedDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        try command("saveEdit")
        let revisedRow = taskRow(named: revised, app: app)
        let editorClosed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !field.exists && !app.otherElements["task-row-editor"].exists && revisedRow.exists && revisedRow.isEnabled
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [editorClosed], timeout: 10), .completed)
        XCTAssertEqual(revisedRow.identifier, identity)
        try command("selectBulkForCancel")
        XCTAssertTrue(app.buttons["task-selection-apply"].waitForExistence(timeout: 5))
        app.buttons["selection-scheduled"].tap()
        app.buttons["selection-date-today"].tap()
        XCTAssertEqual(app.buttons["selection-date-today"].value as? String, "Selected")
        try command("cancelBulkDate")
        XCTAssertTrue(app.datePickers["scheduled-picker"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.buttons["selection-scheduled"].value as? String, "Modified")
        XCTAssertEqual(app.buttons["task-selection-apply"].label, "Apply to 1")
        app.buttons["cancel-task-selection"].tap()
        revisedRow.tap()
        XCTAssertTrue(app.buttons["row-scheduled"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["row-scheduled"].value as? String, "Not set")
        closeTaskRow(app)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !field.exists && !app.otherElements["task-row-editor"].exists && revisedRow.exists && revisedRow.isEnabled
        }, object: nil)], timeout: 10), .completed)
        try command("selectBulkForApply")
        XCTAssertTrue(app.buttons["task-selection-apply"].waitForExistence(timeout: 5))
        app.buttons["selection-deadline"].tap()
        app.buttons["selection-date-tomorrow"].tap()
        try command("applyBulkDate")
        XCTAssertTrue(app.buttons["task-selection-apply"].waitForNonExistence(timeout: 10))
        revisedRow.tap()
        XCTAssertTrue(app.buttons["row-deadline"].waitForExistence(timeout: 5))
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date(timeIntervalSince1970: 1792144800))!
        let deadline = Calendar.current.startOfDay(for: tomorrow).formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: "en_US")))
        XCTAssertEqual(app.buttons["row-deadline"].value as? String, deadline)
        XCTAssertEqual(app.buttons["row-scheduled"].value as? String, "Not set")
        closeTaskRow(app)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !field.exists && !app.otherElements["task-row-editor"].exists && revisedRow.exists && revisedRow.isEnabled
        }, object: nil)], timeout: 10), .completed)
        try command("complete")
        XCTAssertTrue(revisedRow.waitForNonExistence(timeout: 10))
        try command("completedView")
        XCTAssertTrue(revisedRow.waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Done"].isSelected)
        tapTaskControl(app.buttons["workspace-settings"], app: app)
        XCTAssertTrue(app.collectionViews["workspace-settings-list"].waitForExistence(timeout: 10))
        tapTaskControl(app.buttons["close-workspace-settings"], app: app)
        XCTAssertTrue(app.collectionViews["workspace-settings-list"].waitForNonExistence(timeout: 10))
        XCTAssertFalse(field.exists)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        try command("captureAfterReturn")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        focusTaskText(field, app: app)
        field.typeText("Returned workspace n")
        XCTAssertEqual(field.value as? String, "Returned workspace n")
        try command("saveAfterReturn")
        XCTAssertTrue(field.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["capture-confirmation"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Done"].isSelected)
        app.terminate()
        app.launch()
        selectAllTasks(app)
        XCTAssertTrue(taskRow(named: "Returned workspace n", app: app).waitForExistence(timeout: 10))
        selectDoneTasks(app)
        XCTAssertTrue(taskRow(named: revised, app: app).waitForExistence(timeout: 10))
        XCTAssertEqual(taskRow(named: revised, app: app).identifier, identity)
    }
}
