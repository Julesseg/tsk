import XCTest

@MainActor
final class SynchronizationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testConnectionValidationPersistenceAndServerFailureRetainOfflineTask() throws {
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 10))
        app.buttons["new-task"].tap()
        let draft = app.textFields["task-description"].exists ? app.textFields["task-description"] : app.textViews["task-description"]
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        draft.tap()
        draft.typeText("Offline work survives server failure")
        app.buttons["save-task"].tap()
        XCTAssertTrue(waitForTaskSave(app, row: taskRow(named: "Offline work survives server failure", app: app), timeout: 10))
        XCTAssertTrue(revealSynchronizationSettings(app))
        app.buttons["synchronization-settings"].tap()
        let server = app.textFields["sync-server-url"]
        XCTAssertTrue(server.waitForExistence(timeout: 5))
        capture("Synchronization unconfigured", app)
        server.tap()
        server.typeText("http://127.0.0.1:1")
        let secret = app.secureTextFields["sync-encryption-secret"]
        secret.tap()
        secret.typeText("isolated-ui-test-secret")
        if app.buttons["dismiss-sync-keyboard"].exists { app.buttons["dismiss-sync-keyboard"].tap() }
        app.buttons["save-sync-connection"].tap()
        XCTAssertTrue(app.staticTexts["sync-error"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["sync-error"].label.contains("client ID"))
        capture("Connection validation", app)
        let client = app.textFields["sync-client-id"]
        client.tap()
        client.typeText("6F88CFF9-4727-4699-8B5E-EE6D530498E4")
        if app.buttons["dismiss-sync-keyboard"].exists { app.buttons["dismiss-sync-keyboard"].tap() }
        app.buttons["save-sync-connection"].tap()
        XCTAssertTrue(app.staticTexts["sync-connection-saved"].waitForExistence(timeout: 5))
        capture("Connection saved before server verification", app)
        app.buttons["sync-now"].tap()
        XCTAssertTrue(app.staticTexts["sync-error"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["sync-error"].label.contains("locally saved tasks remain"))
        capture("Real server connection failure", app)
        app.buttons["Done"].tap()
        XCTAssertTrue(taskRow(named: "Offline work survives server failure", app: app).exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(taskRow(named: "Offline work survives server failure", app: app).waitForExistence(timeout: 10))
        XCTAssertTrue(revealSynchronizationSettings(app))
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
        XCTAssertTrue(taskRow(named: "Offline work survives server failure", app: app).exists)
    }

    func testSuccessfulManualSynchronizationUsesRealConfiguredServer() throws {
        let environment = ProcessInfo.processInfo.environment
        let serverURL = try XCTUnwrap(environment["TSK_UI_SYNC_SERVER_URL"])
        let clientID = try XCTUnwrap(environment["TSK_UI_SYNC_CLIENT_ID"])
        let secret = try XCTUnwrap(environment["TSK_UI_SYNC_SECRET"])
        let token = try XCTUnwrap(environment["TSK_UI_SYNC_FIXTURE_TOKEN"])
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 10))
        app.buttons["new-task"].tap()
        let draft = app.textFields["task-description"].exists ? app.textFields["task-description"] : app.textViews["task-description"]
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        draft.tap()
        draft.typeText("Hosted task " + token)
        if app.buttons["dismiss-editor-keyboard"].exists { app.buttons["dismiss-editor-keyboard"].tap() }
        app.buttons["save-task"].tap()
        XCTAssertTrue(waitForTaskSave(app, row: taskRow(named: "Hosted task " + token, app: app), timeout: 10))
        XCTAssertTrue(revealSynchronizationSettings(app))
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
        if app.buttons["dismiss-sync-keyboard"].exists { app.buttons["dismiss-sync-keyboard"].tap() }
        app.buttons["save-sync-connection"].tap()
        XCTAssertTrue(app.staticTexts["sync-connection-saved"].waitForExistence(timeout: 5))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["sync-now"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed)
        XCTAssertTrue(revealTaskElement(app.buttons["sync-now"], in: "sync-settings-form", app: app))
        app.buttons["sync-now"].tap()
        XCTAssertTrue(app.staticTexts["Synchronized with server"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.staticTexts["sync-error"].exists)
        capture("Successful manual synchronization with real server", app)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["new-task"].exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(taskRow(named: "Hosted task " + token, app: app).waitForExistence(timeout: 10))
    }

    func testRealFixtureSettingsReachTheUITestRunner() throws {
        let environment = ProcessInfo.processInfo.environment
        let url = try XCTUnwrap(URL(string: XCTUnwrap(environment["TSK_UI_SYNC_SERVER_URL"])))
        XCTAssertEqual(url.host, "127.0.0.1")
        XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(environment["TSK_UI_SYNC_CLIENT_ID"])))
        XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(environment["TSK_UI_SYNC_FIXTURE_TOKEN"])))
        XCTAssertFalse(try XCTUnwrap(environment["TSK_UI_SYNC_SECRET"]).isEmpty)
        let proof = XCTAttachment(string: "Real fixture URL: \(url)\nClient: \(environment["TSK_UI_SYNC_CLIENT_ID"]!)\nToken: \(environment["TSK_UI_SYNC_FIXTURE_TOKEN"]!)")
        proof.name = "Real server settings received by UI runner"
        proof.lifetime = .keepAlways
        add(proof)
    }

    private func revealSynchronizationSettings(_ app: XCUIApplication) -> Bool {
        if app.collectionViews["workspace-sidebar"].exists {
            return revealTaskElement(app.buttons["synchronization-settings"], in: "workspace-sidebar", app: app)
        }
        return app.buttons["synchronization-settings"].waitForExistence(timeout: 10)
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
