import XCTest

final class SynchronizationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testConnectionValidationPersistenceAndServerFailureRetainOfflineTask() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 10))
        app.buttons["new-task"].tap()
        let draft = app.textFields["task-description"].exists ? app.textFields["task-description"] : app.textViews["task-description"]
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        draft.tap()
        draft.typeText("Offline work survives server failure")
        app.buttons["save-task"].tap()
        XCTAssertTrue(app.staticTexts["Offline work survives server failure"].waitForExistence(timeout: 10))
        app.buttons["synchronization-settings"].tap()
        let server = app.textFields["sync-server-url"]
        XCTAssertTrue(server.waitForExistence(timeout: 5))
        capture("Synchronization unconfigured", app)
        server.tap()
        server.typeText("http://127.0.0.1:1")
        let secret = app.secureTextFields["sync-encryption-secret"]
        secret.tap()
        secret.typeText("isolated-ui-test-secret")
        app.buttons["save-sync-connection"].tap()
        XCTAssertTrue(app.staticTexts["sync-error"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["sync-error"].label.contains("client ID"))
        capture("Connection validation", app)
        let client = app.textFields["sync-client-id"]
        client.tap()
        client.typeText("6F88CFF9-4727-4699-8B5E-EE6D530498E4")
        app.buttons["save-sync-connection"].tap()
        XCTAssertTrue(app.staticTexts["sync-connection-saved"].waitForExistence(timeout: 5))
        capture("Connection saved before server verification", app)
        app.buttons["sync-now"].tap()
        XCTAssertTrue(app.staticTexts["sync-error"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["sync-error"].label.contains("locally saved tasks remain"))
        capture("Real server connection failure", app)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Offline work survives server failure"].exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Offline work survives server failure"].waitForExistence(timeout: 10))
        app.buttons["synchronization-settings"].tap()
        XCTAssertTrue(server.waitForExistence(timeout: 5))
        XCTAssertEqual(server.value as? String, "http://127.0.0.1:1")
        XCTAssertEqual(client.value as? String, "6F88CFF9-4727-4699-8B5E-EE6D530498E4")
        capture("Connection retained after relaunch", app)
        app.buttons["sync-now"].tap()
        XCTAssertTrue(app.staticTexts["sync-error"].waitForExistence(timeout: 20))
        app.buttons["Disconnect"].tap()
        XCTAssertEqual(app.staticTexts["sync-status"].label, "Local tasks only")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Offline work survives server failure"].exists)
    }

    func testSuccessfulManualSynchronizationUsesRealConfiguredServer() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let serverURL = environment["TSK_UI_SYNC_SERVER_URL"],
              let clientID = environment["TSK_UI_SYNC_CLIENT_ID"],
              let secret = environment["TSK_UI_SYNC_SECRET"] else {
            throw XCTSkip("Successful server UI flow requires an isolated TaskChampion server fixture.")
        }
        let app = XCUIApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["synchronization-settings"].waitForExistence(timeout: 10))
        app.buttons["synchronization-settings"].tap()
        let server = app.textFields["sync-server-url"]
        XCTAssertTrue(server.waitForExistence(timeout: 5))
        server.tap()
        server.typeText(serverURL)
        let client = app.textFields["sync-client-id"]
        client.tap()
        client.typeText(clientID)
        let encryption = app.secureTextFields["sync-encryption-secret"]
        encryption.tap()
        encryption.typeText(secret)
        app.buttons["save-sync-connection"].tap()
        XCTAssertTrue(app.staticTexts["sync-connection-saved"].waitForExistence(timeout: 5))
        app.buttons["sync-now"].tap()
        XCTAssertTrue(app.staticTexts["Synchronized with server"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.staticTexts["sync-error"].exists)
        capture("Successful manual synchronization with real server", app)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["new-task"].exists)
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
