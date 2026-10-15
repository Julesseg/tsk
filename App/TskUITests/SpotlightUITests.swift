import XCTest

@MainActor final class SpotlightUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testSystemSpotlightOpensExactTaskAndLocalCompletionRemovesIndexEntry() throws {
        let token = UUID().uuidString, title = "tsk local " + UUID().uuidString
        let app = configuredApp(token)
        defer { clean(app) }
        app.launch()
        let id = create(title, app)
        openSettings(app)
        query(app)
        XCTAssertTrue((app.staticTexts["spotlight-fixture-query-ids"].value as? String ?? "").lowercased().contains(id.lowercased()))
        app.buttons["Done"].tap()
        try systemSearch(title, app)
        XCTAssertTrue(app.staticTexts["task-detail-description"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.staticTexts["task-detail-description"].label, title)
        let identity = app.staticTexts[id]
        XCTAssertTrue(revealTaskElement(identity, in: "task-detail-form", app: app))
        capture("Real Spotlight lookup tap opens exact persisted UUID", app)
        XCTAssertTrue(revealTaskElement(app.buttons["complete-task"], in: "task-detail-form", app: app))
        app.buttons["complete-task"].tap()
        app.buttons["Done"].tap()
        openSettings(app); query(app)
        XCTAssertFalse((app.staticTexts["spotlight-fixture-query-ids"].value as? String ?? "").lowercased().contains(id.lowercased()))
        capture("Awaited local completion removes actual indexed UUID", app)
    }

    func testStaleRealSystemResultReportsUnavailableAndNeverOpensAnotherTask() throws {
        let token = UUID().uuidString
        let app = configuredApp(token)
        defer { clean(app) }
        app.launch()
        _ = create("Keep unrelated task " + token, app)
        openSettings(app)
        XCTAssertTrue(revealTaskElement(app.buttons["spotlight-stale-fixture"], in: "spotlight-settings-form", app: app))
        app.buttons["spotlight-stale-fixture"].tap()
        XCTAssertTrue(app.staticTexts["spotlight-fixture-result"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["spotlight-fixture-result"].label.contains("Actual stale fixture entry indexed"))
        app.buttons["Done"].tap()
        try systemSearch("tsk stale " + token, app)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "spotlight-task-unavailable").firstMatch.waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["task-detail-description"].exists)
        capture("Real stale system result resolves unavailable without a replacement task", app)
    }

    func testReceivedEncryptedPeerCompletionReconcilesActualIndex() throws {
        let token = UUID().uuidString
        let app = configuredApp(token)
        for key in ["TSK_UI_SYNC_SERVER_URL", "TSK_UI_SYNC_CLIENT_ID", "TSK_UI_SYNC_SECRET"] {
            app.launchEnvironment[key] = try XCTUnwrap(ProcessInfo.processInfo.environment[key], "Canonical owned sync fixture must be configured")
        }
        defer { clean(app) }
        app.launch()
        let id = create("tsk remote " + token, app)
        openSettings(app); query(app)
        XCTAssertTrue((app.staticTexts["spotlight-fixture-query-ids"].value as? String ?? "").lowercased().contains(id.lowercased()))
        XCTAssertTrue(revealTaskElement(app.buttons["spotlight-sync-fixture"], in: "spotlight-settings-form", app: app))
        app.buttons["spotlight-sync-fixture"].tap()
        XCTAssertTrue(app.staticTexts["spotlight-fixture-result"].waitForExistence(timeout: 45))
        XCTAssertTrue(app.staticTexts["spotlight-fixture-result"].label.contains("Actual encrypted peer completion received"), app.staticTexts["spotlight-query-error"].label)
        query(app)
        XCTAssertFalse((app.staticTexts["spotlight-fixture-query-ids"].value as? String ?? "").lowercased().contains(id.lowercased()))
        capture("Actual received encrypted sync completion reconciles scoped Spotlight index", app)
    }

    private func clean(_ app: XCUIApplication) {
        app.terminate()
        app.launchEnvironment["TSK_TEST_SPOTLIGHT_CLEANUP"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts["spotlight-fixture-cleaned"].waitForExistence(timeout: 20))
        app.terminate()
    }
    private func configuredApp(_ token: String) -> XCUIApplication {
        XCTAssertEqual(ProcessInfo.processInfo.environment["TSK_UI_ISOLATED_SIMULATOR"], "1")
        let app = XCUIApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = token
        app.launchEnvironment["TSK_TEST_SPOTLIGHT_FIXTURE"] = token
        app.launchEnvironment["TSK_UI_ISOLATED_SIMULATOR"] = "1"
        return app
    }
    private func create(_ title: String, _ app: XCUIApplication) -> String {
        XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 20)); app.buttons["new-task"].tap()
        let field = app.descendants(matching: .any).matching(identifier: "task-description").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap(); field.typeText(title)
        if app.buttons["dismiss-editor-keyboard"].exists { app.buttons["dismiss-editor-keyboard"].tap() }
        app.buttons["save-task"].tap()
        let row = taskRow(named: title, app: app)
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        return String(row.identifier.dropFirst("task-".count))
    }
    private func openSettings(_ app: XCUIApplication) {
        if app.collectionViews["workspace-sidebar"].exists {
            XCTAssertTrue(revealTaskElement(app.buttons["spotlight-settings"], in: "workspace-sidebar", app: app))
        } else { app.buttons["workspace-more"].tap() }
        app.buttons["spotlight-settings"].tap()
        XCTAssertTrue(app.buttons["spotlight-query"].waitForExistence(timeout: 10))
    }
    private func query(_ app: XCUIApplication) {
        XCTAssertTrue(revealTaskElement(app.buttons["spotlight-query"], in: "spotlight-settings-form", app: app))
        app.buttons["spotlight-query"].tap()
        XCTAssertTrue(app.staticTexts["spotlight-query-result"].waitForExistence(timeout: 20), app.staticTexts["spotlight-query-error"].label)
        XCTAssertTrue(revealTaskElement(app.staticTexts["spotlight-fixture-query-ids"], in: "spotlight-settings-form", app: app))
        XCTAssertNotNil(app.staticTexts["spotlight-fixture-query-ids"].value as? String)
    }
    private func systemSearch(_ title: String, _ app: XCUIApplication) throws {
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.swipeDown()
        let search = springboard.searchFields.firstMatch.exists ? springboard.searchFields.firstMatch : springboard.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 15), "Actual system Spotlight search field must be available")
        search.tap(); search.typeText(title)
        let result = springboard.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 30), "Indexed task must appear in actual system Spotlight, independently of CSSearchQuery proof")
        let screenshot = XCTAttachment(screenshot: springboard.screenshot()); screenshot.name = "Actual system Spotlight result"; screenshot.lifetime = .keepAlways; add(screenshot)
        result.tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
    }
    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
