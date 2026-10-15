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
        query(app, id: id, present: true)
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
        openSettings(app); query(app, id: id, present: false)
        capture("Confirmed local completion removes actual indexed UUID", app)
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
        XCTAssertTrue(app.staticTexts["spotlight-fixture-result"].waitForExistence(timeout: 60))
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
        openSettings(app); query(app, id: id, present: true)
        XCTAssertTrue(revealTaskElement(app.buttons["spotlight-sync-fixture"], in: "spotlight-settings-form", app: app))
        app.buttons["spotlight-sync-fixture"].tap()
        XCTAssertTrue(app.staticTexts["spotlight-fixture-result"].waitForExistence(timeout: 45))
        XCTAssertTrue(app.staticTexts["spotlight-fixture-result"].label.contains("Actual encrypted peer completion received"), app.staticTexts["spotlight-query-error"].label)
        query(app, id: id, present: false)
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
        XCTAssertTrue(waitForTaskSave(app, row: row, timeout: 20))
        return String(row.identifier.dropFirst("task-".count))
    }
    private func openSettings(_ app: XCUIApplication) {
        if app.collectionViews["workspace-sidebar"].exists {
            XCTAssertTrue(revealTaskElement(app.buttons["spotlight-settings"], in: "workspace-sidebar", app: app))
        } else { app.buttons["workspace-more"].tap() }
        tapTaskControl(app.buttons["spotlight-settings"], app: app)
        XCTAssertTrue(app.buttons["spotlight-query"].waitForExistence(timeout: 10))
    }
    private func query(_ app: XCUIApplication, id: String, present: Bool) {
        let deadline = Date().addingTimeInterval(60)
        let button = app.buttons["spotlight-query"]
        let ids = app.staticTexts["spotlight-fixture-query-ids"]
        XCTAssertTrue(revealTaskElement(button, in: "spotlight-settings-form", app: app))
        repeat {
            if button.isEnabled { button.tap() }
            let finished = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                button.isEnabled && app.staticTexts["spotlight-query-result"].exists
            }, object: nil)
            guard XCTWaiter.wait(for: [finished], timeout: max(0, deadline.timeIntervalSinceNow)) == .completed else { break }
            if ids.exists, let values = ids.value as? String,
               values.lowercased().contains(id.lowercased()) == present,
               !app.staticTexts["spotlight-index-pending"].exists { return }
            RunLoop.current.run(until: Date().addingTimeInterval(min(0.25, max(0, deadline.timeIntervalSinceNow))))
        } while Date() < deadline
        capture("Actual Spotlight membership did not settle within the bounded 60-second query budget", app)
        let observed = ids.exists ? String(describing: ids.value) : "Query IDs not present"
        let error = app.staticTexts["spotlight-query-error"]
        let message = error.exists ? error.label : "No query error label"
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Actual Spotlight membership failure accessibility endpoint"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        XCTFail("Actual indexed UUID membership must become \(present ? "present" : "absent"): \(id). Observed \(observed); \(message); pending=\(app.staticTexts["spotlight-index-pending"].exists)")
    }
    private func systemSearch(_ title: String, _ app: XCUIApplication) throws {
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.swipeDown()
        capture("Actual system Search surface before first-run handling", springboard)
        let education = springboard.buttons["Continue"].firstMatch
        if education.exists && education.isHittable {
            education.tap()
            capture("Actual system Search surface after native Continue", springboard)
        }
        let spotlight = XCUIApplication(bundleIdentifier: "com.apple.Spotlight")
        let owners = [("com.apple.springboard", springboard), ("com.apple.Spotlight", spotlight)]
        func readySearch() -> (owner: XCUIApplication, field: XCUIElement)? {
            for (_, owner) in owners {
                let field = owner.searchFields.firstMatch
                if field.exists && field.isEnabled && field.isHittable { return (owner, field) }
            }
            let fallback = springboard.textFields.firstMatch
            if fallback.exists && fallback.isEnabled && fallback.isHittable { return (springboard, fallback) }
            return nil
        }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in readySearch() != nil }, object: nil)
        guard XCTWaiter.wait(for: [ready], timeout: 15) == .completed, let selected = readySearch() else {
            capture("Actual Search endpoint after missing accessible search field", springboard)
            for (bundle, owner) in owners {
                let raw = owner.debugDescription
                let hierarchy = XCTAttachment(string: "state=\(owner.state.rawValue); truncated=\(raw.count > 16384)\n" + String(raw.prefix(16384)))
                hierarchy.name = "Actual Search \(bundle) accessibility endpoint"; hierarchy.lifetime = .keepAlways; add(hierarchy)
            }
            XCTFail("Actual system Spotlight search field must be available, enabled and hittable on an observed native owner")
            return
        }
        selected.field.tap(); selected.field.typeText(title)
        let result = selected.owner.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 30), "Indexed task must appear in actual system Spotlight, independently of CSSearchQuery proof")
        let screenshot = XCTAttachment(screenshot: selected.owner.screenshot()); screenshot.name = "Actual system Spotlight result"; screenshot.lifetime = .keepAlways; add(screenshot)
        result.tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
    }
    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
