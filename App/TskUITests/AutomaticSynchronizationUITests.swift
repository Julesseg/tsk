import XCTest

final class AutomaticSynchronizationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testAutomaticFailureKeepsCaptureAvailableAndRetriesOnRelaunch() throws {
        addUIInterruptionMonitor(withDescription: "Optional system password storage") { alert in
            guard alert.label == "Save Password?", alert.buttons["Not Now"].exists else { return false }
            alert.buttons["Not Now"].tap()
            return true
        }
        let app = XCUIApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["synchronization-settings"].waitForExistence(timeout: 10))
        app.buttons["synchronization-settings"].tap()
        let server = app.textFields["sync-server-url"]
        XCTAssertTrue(server.waitForExistence(timeout: 5))
        server.tap()
        server.typeText("http://127.0.0.1:1")
        let client = app.textFields["sync-client-id"]
        client.tap()
        client.typeText("6F88CFF9-4727-4699-8B5E-EE6D530498E4")
        let secret = app.secureTextFields["sync-encryption-secret"]
        secret.tap()
        secret.typeText("isolated-ui-test-secret")
        app.buttons["save-sync-connection"].tap()
        XCTAssertTrue(app.staticTexts["sync-error"].waitForExistence(timeout: 20))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["task-sync-error"].waitForExistence(timeout: 10))
        capture("Automatic synchronization failure with local capture available", app)
        app.buttons["new-task"].tap()
        let description = app.textFields["task-description"].exists ? app.textFields["task-description"] : app.textViews["task-description"]
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        focusTaskText(description, app: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        description.typeText("Durable work while automatic sync fails")
        XCTAssertEqual(description.value as? String, "Durable work while automatic sync fails")
        XCTAssertTrue(app.buttons["dismiss-editor-keyboard"].waitForExistence(timeout: 5))
        app.buttons["dismiss-editor-keyboard"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["save-task"].isHittable)
        app.buttons["save-task"].tap()
        XCTAssertTrue(waitForTaskSave(app, row: taskRow(named: "Durable work while automatic sync fails", app: app), timeout: 10))
        XCTAssertTrue(app.staticTexts["Durable work while automatic sync fails"].exists)
        XCTAssertTrue(app.staticTexts["task-sync-error"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["retry-task-sync"].exists)
        capture("Saved locally despite automatic network failure", app)
        app.buttons["retry-task-sync"].tap()
        XCTAssertTrue(app.staticTexts["task-sync-error"].waitForExistence(timeout: 20))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Durable work while automatic sync fails"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["task-sync-error"].waitForExistence(timeout: 20))
        capture("App opening retries without losing local work", app)
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
