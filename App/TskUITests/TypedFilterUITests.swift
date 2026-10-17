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
        focusTaskText(description, app: app)
        description.typeText("Typed view task")
        tapTaskControl(app.buttons["save-task"], app: app)
        XCTAssertTrue(taskRow(named: "Typed view task", app: app).waitForExistence(timeout: 10))
        taskRow(named: "Typed view task", app: app).tap()
        openAdvanced(app)
        app.buttons["manage-attribute-definitions"].tap()
        addDefinition("score", type: "Numeric", app: app)
        addDefinition("rating", type: "String", app: app, orderedValues: "high\nmid\nlow\n")
        app.buttons["Done"].tap()
        setDateSwitch("uda-enabled-score", to: true, app: app, in: "advanced-attributes-form", keyboardDismissIdentifier: "dismiss-attributes-keyboard")
        replaceScore("3", app: app)
        setDateSwitch("uda-enabled-rating", to: true, app: app, in: "advanced-attributes-form", keyboardDismissIdentifier: "dismiss-attributes-keyboard")
        let rating = app.buttons["uda-value-rating"]
        XCTAssertTrue(revealTaskElement(rating, in: "advanced-attributes-form", app: app))
        for value in ["mid", "high"] {
            tapTaskControl(rating, app: app)
            let option = app.buttons[value]
            tapTaskMenuItem(option, app: app)
            XCTAssertTrue(option.waitForNonExistence(timeout: 5), "Rating menu did not dismiss after selecting \(value)")
            XCTAssertTrue(rating.staticTexts[value].exists, "Rating did not become \(value)")
        }
        tapTaskControl(app.buttons["save-advanced-attributes"], app: app)
        XCTAssertTrue(app.buttons["save-advanced-attributes"].waitForNonExistence(timeout: 10))
        if !isPad { app.navigationBars.buttons.element(boundBy: 0).tap() }
        openViews(app, isPad: isPad)
        app.buttons["new-custom-view"].tap()
        let name = app.textFields["custom-view-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        focusTaskText(name, app: app)
        name.typeText("High rated scores")
        let expression = app.textViews["raw-filter-expression"]
        XCTAssertTrue(revealTaskElement(expression, in: "raw-filter-form", app: app))
        expression.tap()
        expression.typeText("score.above:2 and rating.above:mid")
        app.buttons["dismiss-filter-keyboard"].tap()
        tapTaskControl(app.buttons["save-custom-view"], app: app)
        XCTAssertTrue(app.buttons["save-custom-view"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(taskRow(named: "Typed view task", app: app).waitForExistence(timeout: 10))
        capture("Typed numeric and configured-order result", app: app)
        taskRow(named: "Typed view task", app: app).tap()
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

    func testComputedArithmeticViewErrorsEditsReopenAndCompletion() throws {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        if isPad { XCUIDevice.shared.orientation = .landscapeLeft }
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_NOW"] = "1792144800"
        app.launch()
        XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 10))
        app.buttons["new-task"].tap()
        let description = app.descendants(matching: .any).matching(identifier: "task-description").firstMatch
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        description.tap()
        description.typeText("Computed urgency task")
        app.buttons["dismiss-editor-keyboard"].tap()
        XCTAssertTrue(revealTaskElement(app.buttons["task-priority"], in: "task-editor-form", app: app))
        app.buttons["task-priority"].tap()
        app.buttons["Medium"].tap()
        tapTaskControl(app.buttons["save-task"], app: app)
        XCTAssertTrue(taskRow(named: "Computed urgency task", app: app).waitForExistence(timeout: 10))
        openViews(app, isPad: isPad)
        app.buttons["new-custom-view"].tap()
        let name = app.textFields["custom-view-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Default urgency arithmetic")
        app.buttons["dismiss-filter-keyboard"].tap()
        replaceExpression("urgency / 0 > 0", app: app)
        XCTAssertTrue(revealTaskElement(app.buttons["check-filter"], in: "raw-filter-form", app: app))
        app.buttons["check-filter"].tap()
        XCTAssertTrue(app.staticTexts["filter-error"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["filter-error"].label.contains("zero"))
        capture("Computed expression error retains editable draft", app: app)
        replaceExpression("urgency + 1 > 4.9 and +PENDING", app: app)
        tapTaskControl(app.buttons["save-custom-view"], app: app)
        XCTAssertTrue(app.buttons["save-custom-view"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(taskRow(named: "Computed urgency task", app: app).waitForExistence(timeout: 10))
        capture("Default Float urgency arithmetic selects Medium priority", app: app)
        taskRow(named: "Computed urgency task", app: app).tap()
        XCTAssertTrue(app.buttons["edit-task"].waitForExistence(timeout: 5))
        app.buttons["edit-task"].tap()
        XCTAssertTrue(revealTaskElement(app.buttons["task-priority"], in: "task-editor-form", app: app))
        app.buttons["task-priority"].tap()
        tapTaskControl(app.buttons["Low"], app: app)
        app.buttons["save-task"].tap()
        XCTAssertTrue(app.buttons["save-task"].waitForNonExistence(timeout: 10))
        if !isPad { app.navigationBars.buttons.element(boundBy: 0).tap() }
        XCTAssertTrue(app.staticTexts["No matching tasks"].waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        openViews(app, isPad: isPad)
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "saved-view-")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.swipeLeft()
        app.buttons["Edit"].firstMatch.tap()
        XCTAssertTrue(app.textViews["raw-filter-expression"].waitForExistence(timeout: 5))
        replaceExpression("(urgency + 1 > 2.7) and +PENDING", app: app)
        tapTaskControl(app.buttons["save-custom-view"], app: app)
        XCTAssertTrue(app.buttons["save-custom-view"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(taskRow(named: "Computed urgency task", app: app).waitForExistence(timeout: 10))
        capture("Edited arithmetic definition survives relaunch and updates membership", app: app)
        taskRow(named: "Computed urgency task", app: app).tap()
        XCTAssertTrue(revealTaskElement(app.buttons["complete-task"], in: "task-detail-form", app: app))
        app.buttons["complete-task"].tap()
        XCTAssertTrue(app.staticTexts["task-detail-status"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["task-detail-status"].label.contains("Completed"))
        if !isPad { app.navigationBars.buttons.element(boundBy: 0).tap() }
        XCTAssertTrue(app.staticTexts["No matching tasks"].waitForExistence(timeout: 10))
        capture("Completion refreshes the same explicit pending arithmetic filter", app: app)
    }

    private func replaceExpression(_ value: String, app: XCUIApplication) {
        let expression = app.textViews["raw-filter-expression"]
        XCTAssertTrue(revealTaskElement(expression, in: "raw-filter-form", app: app))
        replaceTaskText(expression, with: value, app: app)
        app.buttons["dismiss-filter-keyboard"].tap()
    }

    private func addDefinition(_ name: String, type: String, app: XCUIApplication, orderedValues: String? = nil) {
        app.buttons["new-attribute-definition"].tap()
        let nameField = app.textFields["attribute-definition-name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        focusTaskText(nameField, app: app)
        nameField.typeText(name)
        app.buttons["dismiss-definition-keyboard"].tap()
        app.buttons["attribute-definition-type"].tap()
        tapTaskControl(app.buttons[type], app: app)
        if let orderedValues {
            setDateSwitch("attribute-values-enabled", to: true, app: app, in: "attribute-definition-form", keyboardDismissIdentifier: "dismiss-definition-keyboard")
            let values = app.textViews["attribute-ordered-values"]
            XCTAssertTrue(revealTaskElement(values, in: "attribute-definition-form", app: app))
            values.tap()
            values.typeText(orderedValues)
            app.buttons["dismiss-definition-keyboard"].tap()
            capture("Local allowed string values in declared order", app: app)
        }
        tapTaskControl(app.buttons["save-attribute-definition"], app: app)
        XCTAssertTrue(nameField.waitForNonExistence(timeout: 10))
    }

    private func replaceScore(_ value: String, app: XCUIApplication) {
        let field = app.descendants(matching: .any).matching(identifier: "uda-value-score").firstMatch
        XCTAssertTrue(revealTaskElement(field, in: "advanced-attributes-form", app: app))
        replaceTaskText(field, with: value, app: app)
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
