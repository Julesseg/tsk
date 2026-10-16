import UIKit
import XCTest

@MainActor
final class TaskAttributeUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testLocalDefinitionsAllFiveTypedValuesValidationAndPersistentReopen() throws {
        if UIDevice.current.userInterfaceIdiom == .pad { XCUIDevice.shared.orientation = .landscapeLeft }
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_NOW"] = "1792144800"
        app.launch()
        XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 10))
        app.buttons["new-task"].tap()
        let description = field("task-description", app: app)
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        focusTaskText(description, app: app)
        description.typeText("Task with local typed values")
        app.buttons["save-task"].tap()
        XCTAssertTrue(description.waitForNonExistence(timeout: 10))
        XCTAssertTrue(taskRow(named: "Task with local typed values", app: app).waitForExistence(timeout: 10))
        taskRow(named: "Task with local typed values", app: app).tap()
        openAdvanced(app)
        app.buttons["manage-attribute-definitions"].tap()
        XCTAssertTrue(app.buttons["new-attribute-definition"].waitForExistence(timeout: 5))
        capture("Local definitions empty", app: app)
        for (name, type) in [("note", "String"), ("score", "Numeric"), ("review", "Date"), ("effort", "Duration"), ("reference", "UUID")] {
            app.buttons["new-attribute-definition"].tap()
            let nameField = app.textFields["attribute-definition-name"]
            XCTAssertTrue(nameField.waitForExistence(timeout: 5))
            focusTaskText(nameField, app: app)
            nameField.typeText(name)
            if app.buttons["dismiss-definition-keyboard"].exists { app.buttons["dismiss-definition-keyboard"].tap() }
            app.buttons["attribute-definition-type"].tap()
            tapTaskMenuItem(app.buttons[type], app: app)
            if name == "reference" { capture("Native UUID definition editor", app: app) }
            tapTaskControl(app.buttons["save-attribute-definition"], app: app)
            XCTAssertTrue(nameField.waitForNonExistence(timeout: 10))
        }
        capture("All five local attribute types", app: app)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["save-advanced-attributes"].waitForExistence(timeout: 5))
        setValue("note", to: "Local note", app: app)
        setValue("score", to: "invalid", app: app)
        app.buttons["save-advanced-attributes"].tap()
        XCTAssertTrue(app.staticTexts["advanced-attributes-error"].waitForExistence(timeout: 5))
        capture("Typed numeric validation remains visible", app: app)
        replaceValue("score", with: "-1.25", app: app)
        XCTAssertTrue(revealTaskElement(app.switches["uda-enabled-effort"].firstMatch, in: "advanced-attributes-form", app: app, initialScrollUp: false))
        setValue("effort", to: "1.5h", app: app)
        setValue("reference", to: "abcdef12", app: app)
        setDateSwitch("uda-enabled-review", to: true, app: app, in: "advanced-attributes-form", keyboardDismissIdentifier: "dismiss-attributes-keyboard")
        capture("Advanced native date and typed values", app: app)
        app.buttons["save-advanced-attributes"].tap()
        XCTAssertTrue(app.buttons["save-advanced-attributes"].waitForNonExistence(timeout: 10))
        app.terminate()
        app.launch()
        XCTAssertTrue(taskRow(named: "Task with local typed values", app: app).waitForExistence(timeout: 10))
        taskRow(named: "Task with local typed values", app: app).tap()
        openAdvanced(app)
        XCTAssertTrue(revealTaskElement(field("uda-value-score", app: app), in: "advanced-attributes-form", app: app))
        XCTAssertEqual(field("uda-value-score", app: app).value as? String, "-1.25")
        XCTAssertTrue(revealTaskElement(field("uda-value-effort", app: app), in: "advanced-attributes-form", app: app, initialScrollUp: false))
        XCTAssertEqual(field("uda-value-effort", app: app).value as? String, "PT1H30M")
        XCTAssertTrue(revealTaskElement(field("uda-value-reference", app: app), in: "advanced-attributes-form", app: app))
        XCTAssertEqual(field("uda-value-reference", app: app).value as? String, "abcdef12")
        setDateSwitch("uda-enabled-reference", to: false, app: app, in: "advanced-attributes-form", keyboardDismissIdentifier: "dismiss-attributes-keyboard")
        XCTAssertTrue(field("uda-value-reference", app: app).waitForNonExistence(timeout: 5))
        capture("Reopened typed values and explicit removal", app: app)
        app.buttons["save-advanced-attributes"].tap()
        XCTAssertTrue(app.buttons["save-advanced-attributes"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(revealTaskElement(app.staticTexts["task-detail-description"], in: "task-detail-form", app: app, initialScrollUp: false))
        XCTAssertEqual(app.staticTexts["task-detail-description"].label, "Task with local typed values")
        app.terminate()
        app.launch()
        XCTAssertTrue(taskRow(named: "Task with local typed values", app: app).waitForExistence(timeout: 10))
        taskRow(named: "Task with local typed values", app: app).tap()
        openAdvanced(app)
        let removedReference = app.switches["uda-enabled-reference"].firstMatch
        XCTAssertTrue(revealTaskElement(removedReference, in: "advanced-attributes-form", app: app))
        XCTAssertEqual(removedReference.value as? String, "0")
        XCTAssertFalse(field("uda-value-reference", app: app).exists)
        app.buttons["manage-attribute-definitions"].tap()
        let scoreDefinition = app.buttons["attribute-definition-score"]
        XCTAssertTrue(revealTaskElement(scoreDefinition, in: "attribute-definitions-list", app: app))
        scoreDefinition.swipeLeft()
        app.buttons["Remove definition"].tap()
        XCTAssertTrue(scoreDefinition.waitForNonExistence(timeout: 10))
        app.buttons["Done"].tap()
        app.buttons["Cancel"].tap()
        let storedScore = app.descendants(matching: .any).matching(identifier: "raw-attribute-score").firstMatch
        XCTAssertTrue(revealTaskElement(storedScore, in: "task-detail-form", app: app))
        XCTAssertEqual(storedScore.value as? String, "-1.25")
        capture("Removing a local definition keeps the raw task value", app: app)
    }

    private func openAdvanced(_ app: XCUIApplication) {
        XCTAssertTrue(revealTaskElement(app.buttons["advanced-attributes"], in: "task-detail-form", app: app))
        app.buttons["advanced-attributes"].tap()
        XCTAssertTrue(app.buttons["manage-attribute-definitions"].waitForExistence(timeout: 5))
    }

    private func setValue(_ name: String, to value: String, app: XCUIApplication) {
        setDateSwitch("uda-enabled-\(name)", to: true, app: app, in: "advanced-attributes-form", keyboardDismissIdentifier: "dismiss-attributes-keyboard")
        replaceValue(name, with: value, app: app)
    }

    private func replaceValue(_ name: String, with value: String, app: XCUIApplication) {
        let valueField = field("uda-value-\(name)", app: app)
        XCTAssertTrue(revealTaskElement(valueField, in: "advanced-attributes-form", app: app))
        valueField.tap()
        valueField.typeKey("a", modifierFlags: .command)
        valueField.typeText(value)
        if app.buttons["dismiss-attributes-keyboard"].exists { app.buttons["dismiss-attributes-keyboard"].tap() }
    }

    private func field(_ identifier: String, app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
