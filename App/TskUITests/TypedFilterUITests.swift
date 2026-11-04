import UIKit
import XCTest

@MainActor
final class TypedFilterUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testComputedArithmeticViewErrorsEditsReopenAndCompletion() throws {
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_NOW"] = "1792144800"
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 10))
        app.buttons["New task"].tap()
        let description = app.descendants(matching: .any).matching(identifier: "task-description").firstMatch
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        description.tap()
        description.typeText("Computed urgency task")
        dismissKeyboard("dismiss-editor-keyboard", app: app)
        XCTAssertTrue(revealTaskElement(app.buttons["task-priority"], in: "task-editor-form", app: app))
        app.buttons["task-priority"].tap()
        app.buttons["Medium"].tap()
        tapTaskControl(app.buttons["save-task"], app: app)
        XCTAssertTrue(taskRow(named: "Computed urgency task", app: app).waitForExistence(timeout: 10))
        openViews(app)
        app.buttons["new-custom-view"].tap()
        let name = app.textFields["custom-view-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Default urgency arithmetic")
        dismissKeyboard("dismiss-filter-keyboard", app: app)
        replaceExpression("urgency / 0 > 0", app: app)
        XCTAssertTrue(revealTaskElement(app.buttons["check-filter"], in: "raw-filter-form", app: app))
        app.buttons["check-filter"].tap()
        XCTAssertTrue(app.staticTexts["filter-error"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["filter-error"].label.contains("zero"))
        capture("Computed expression error retains editable draft", app: app)
        replaceExpression("urgency + 1 > 4.9 and +PENDING", app: app)
        tapTaskControl(app.buttons["save-custom-view"], app: app)
        XCTAssertTrue(app.buttons["save-custom-view"].waitForNonExistence(timeout: 10))
        activateSavedWorkspaceView(app)
        XCTAssertTrue(taskRow(named: "Computed urgency task", app: app).waitForExistence(timeout: 10))
        capture("Default Float urgency arithmetic selects Medium priority", app: app)
        openTaskInformation(taskRow(named: "Computed urgency task", app: app), app: app)
        XCTAssertTrue(app.buttons["edit-task"].waitForExistence(timeout: 5))
        app.buttons["edit-task"].tap()
        XCTAssertTrue(revealTaskElement(app.buttons["task-priority"], in: "task-editor-form", app: app))
        app.buttons["task-priority"].tap()
        tapTaskControl(app.buttons["Low"], app: app)
        app.buttons["save-task"].tap()
        XCTAssertTrue(app.buttons["save-task"].waitForNonExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["No matching tasks"].waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        openViews(app)
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "saved-view-")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        openSavedViewOptions(app)
        app.buttons["Edit"].firstMatch.tap()
        XCTAssertTrue(app.textViews["raw-filter-expression"].waitForExistence(timeout: 5))
        replaceExpression("(urgency + 1 > 2.7) and +PENDING", app: app)
        tapTaskControl(app.buttons["save-custom-view"], app: app)
        XCTAssertTrue(app.buttons["save-custom-view"].waitForNonExistence(timeout: 10))
        activateSavedWorkspaceView(app)
        XCTAssertTrue(taskRow(named: "Computed urgency task", app: app).waitForExistence(timeout: 10))
        capture("Edited arithmetic definition survives relaunch and updates membership", app: app)
        openTaskInformation(taskRow(named: "Computed urgency task", app: app), app: app)
        XCTAssertTrue(revealTaskElement(app.buttons["complete-task"], in: "task-detail-form", app: app))
        app.buttons["complete-task"].tap()
        XCTAssertTrue(app.staticTexts["task-detail-status"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["task-detail-status"].label.contains("Completed"))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["No matching tasks"].waitForExistence(timeout: 10))
        capture("Completion refreshes the same explicit pending arithmetic filter", app: app)
    }

    private func replaceExpression(_ value: String, app: XCUIApplication) {
        let expression = app.textViews["raw-filter-expression"]
        XCTAssertTrue(revealTaskElement(expression, in: "raw-filter-form", app: app))
        replaceTaskText(expression, with: value, app: app)
        dismissKeyboard("dismiss-filter-keyboard", app: app)
        XCTAssertTrue(app.buttons["save-custom-view"].exists)
    }

    private func dismissKeyboard(_ identifier: String, app: XCUIApplication) {
        tapTaskControlAtCenter(app.buttons[identifier], app: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
    }

    private func openViews(_ app: XCUIApplication) {
        openWorkspaceSetting("custom-views", app: app)
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
