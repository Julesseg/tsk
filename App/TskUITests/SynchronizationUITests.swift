import XCTest

@MainActor
final class SynchronizationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testConnectionValidationPersistenceAndServerFailureRetainOfflineTask() throws {
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 10))
        app.buttons["New task"].tap()
        let draft = app.descendants(matching: .any).matching(identifier: "task-description").firstMatch
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        draft.tap()
        draft.typeText("Offline work survives server failure")
        XCTAssertEqual(draft.value as? String, "Offline work survives server failure")
        let keyboardDone = app.buttons[taskEditorKeyboardDismissIdentifier(app)]
        XCTAssertTrue(keyboardDone.waitForExistence(timeout: 5))
        tapTaskControlAtCenter(keyboardDone, app: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        tapTaskControl(taskEditorSaveButton(app), app: app)
        XCTAssertTrue(waitForTaskSave(app, named: "Offline work survives server failure", timeout: 10))
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
        if app.buttons["dismiss-sync-keyboard"].exists { tapTaskControlAtCenter(app.buttons["dismiss-sync-keyboard"], app: app) }
        app.buttons["save-sync-connection"].tap()
        XCTAssertTrue(app.staticTexts["sync-error"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["sync-error"].label.contains("client ID"))
        capture("Connection validation", app)
        let client = app.textFields["sync-client-id"]
        client.tap()
        client.typeText("6F88CFF9-4727-4699-8B5E-EE6D530498E4")
        if app.buttons["dismiss-sync-keyboard"].exists { tapTaskControlAtCenter(app.buttons["dismiss-sync-keyboard"], app: app) }
        app.buttons["save-sync-connection"].tap()
        XCTAssertTrue(app.staticTexts["sync-connection-saved"].waitForExistence(timeout: 5))
        capture("Connection saved before server verification", app)
        app.buttons["sync-now"].tap()
        XCTAssertTrue(app.staticTexts["sync-error"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["sync-error"].label.contains("locally saved tasks remain"))
        capture("Real server connection failure", app)
        app.navigationBars.buttons["Done"].tap()
        XCTAssertTrue(taskRow(named: "Offline work survives server failure", app: app).exists)
        app.terminate()
        app.launch()
        selectAllTasks(app)
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
        app.navigationBars.buttons["Done"].tap()
        XCTAssertTrue(taskRow(named: "Offline work survives server failure", app: app).exists)
    }

    private func revealSynchronizationSettings(_ app: XCUIApplication) -> Bool {
        revealWorkspaceSetting("synchronization-settings", app: app)
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
