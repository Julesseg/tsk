import UIKit
import XCTest

@MainActor
final class TypedFilterUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testTypedSavedViewMembershipAfterEditingAndPersistentReopen() throws {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        if isPad { XCUIDevice.shared.orientation = .landscapeLeft }
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 10))
        app.buttons["new-task"].tap()
        let description = app.descendants(matching: .any).matching(identifier: "task-description").firstMatch
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        description.typeText("Typed view task")
        app.buttons["save-task"].tap()
        XCTAssertTrue(app.staticTexts["Typed view task"].firstMatch.waitForExistence(timeout: 10))
        app.staticTexts["Typed view task"].firstMatch.tap()
        openAdvanced(app)
        app.buttons["manage-attribute-definitions"].tap()
        addDefinition("score", type: "Numeric", app: app)
        addDefinition("rating", type: "String", app: app, orderedValues: "high\nmid\nlow\n")
        app.buttons["Done"].tap()
        setDateSwitch("uda-enabled-score", to: true, app: app, in: "advanced-attributes-form", keyboardDismissIdentifier: "dismiss-attributes-keyboard")
        replaceScore("3", app: app)
        setDateSwitch("uda-enabled-rating", to: true, app: app, in: "advanced-attributes-form", keyboardDismissIdentifier: "dismiss-attributes-keyboard")
        XCTAssertTrue(revealTaskElement(app.buttons["uda-value-rating"], in: "advanced-attributes-form", app: app))
        app.buttons["uda-value-rating"].tap()
        app.buttons["high"].tap()
        app.buttons["save-advanced-attributes"].tap()
        XCTAssertTrue(app.buttons["save-advanced-attributes"].waitForNonExistence(timeout: 10))
        if !isPad { app.navigationBars.buttons.element(boundBy: 0).tap() }
        openViews(app, isPad: isPad)
        app.buttons["new-custom-view"].tap()
        let name = app.textFields["custom-view-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText("High rated scores")
        let expression = app.textViews["raw-filter-expression"]
        XCTAssertTrue(revealTaskElement(expression, in: "raw-filter-form", app: app))
        expression.tap()
        expression.typeText("score.above:2 and rating.above:mid")
        app.buttons["dismiss-filter-keyboard"].tap()
        app.buttons["save-custom-view"].tap()
        XCTAssertTrue(app.staticTexts["Typed view task"].firstMatch.waitForExistence(timeout: 10))
        capture("Typed numeric and configured-order result", app: app)
        app.staticTexts["Typed view task"].firstMatch.tap()
        openAdvanced(app)
        replaceScore("invalid", app: app)
        app.buttons["save-advanced-attributes"].tap()
        XCTAssertTrue(app.staticTexts["advanced-attributes-error"].waitForExistence(timeout: 5))
        capture("Invalid typed edit preserves draft and stored view membership", app: app)
        replaceScore("1", app: app)
        app.buttons["save-advanced-attributes"].tap()
        XCTAssertTrue(app.buttons["save-advanced-attributes"].waitForNonExistence(timeout: 10))
        if !isPad { app.navigationBars.buttons.element(boundBy: 0).tap() }
        XCTAssertTrue(app.staticTexts["No matching tasks"].waitForExistence(timeout: 10))
        capture("Valid numeric edit removes result from saved expression", app: app)
        app.terminate()
        app.launch()
        openViews(app, isPad: isPad)
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "saved-view-")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.tap()
        XCTAssertTrue(app.staticTexts["No matching tasks"].waitForExistence(timeout: 10))
        capture("Typed definitions and saved filter after relaunch", app: app)
    }

    private func addDefinition(_ name: String, type: String, app: XCUIApplication, orderedValues: String? = nil) {
        app.buttons["new-attribute-definition"].tap()
        let nameField = app.textFields["attribute-definition-name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.typeText(name)
        app.buttons["dismiss-definition-keyboard"].tap()
        app.buttons["attribute-definition-type"].tap()
        app.buttons[type].tap()
        if let orderedValues {
            setDateSwitch("attribute-values-enabled", to: true, app: app, in: "attribute-definition-form", keyboardDismissIdentifier: "dismiss-definition-keyboard")
            let values = app.textViews["attribute-ordered-values"]
            XCTAssertTrue(revealTaskElement(values, in: "attribute-definition-form", app: app))
            values.tap()
            values.typeText(orderedValues)
            app.buttons["dismiss-definition-keyboard"].tap()
            capture("Local allowed string values in declared order", app: app)
        }
        app.buttons["save-attribute-definition"].tap()
        XCTAssertTrue(nameField.waitForNonExistence(timeout: 10))
    }

    private func replaceScore(_ value: String, app: XCUIApplication) {
        let field = app.descendants(matching: .any).matching(identifier: "uda-value-score").firstMatch
        XCTAssertTrue(revealTaskElement(field, in: "advanced-attributes-form", app: app))
        field.tap()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(value)
        app.buttons["dismiss-attributes-keyboard"].tap()
    }

    private func openAdvanced(_ app: XCUIApplication) {
        XCTAssertTrue(revealTaskElement(app.buttons["advanced-attributes"], in: "task-detail-form", app: app))
        app.buttons["advanced-attributes"].tap()
        XCTAssertTrue(app.buttons["manage-attribute-definitions"].waitForExistence(timeout: 5))
    }

    private func openViews(_ app: XCUIApplication, isPad: Bool) {
        if isPad { XCTAssertTrue(revealTaskElement(app.buttons["custom-views"], in: "workspace-sidebar", app: app)) }
        XCTAssertTrue(app.buttons["custom-views"].waitForExistence(timeout: 10))
        app.buttons["custom-views"].tap()
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
