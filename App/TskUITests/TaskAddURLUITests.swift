import XCTest

@MainActor final class TaskAddURLUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testSystemAddURLAppearsInCurrentListWithoutOpeningAnEditorAndPersistsAfterRelaunch() throws {
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launch()
        selectAllTasks(app)
        defer { app.terminate() }
        let host = try send("tsk://add?description=URL%20train&project=Travel&tags=trip&priority=H&scheduled=2026-11-05T10%3A30%3A00%2B02%3A00&deadline=2026-11-06T08%3A00%3A00Z&waiting-until=2026-11-04T09%3A00%3A00Z")
        defer { host.terminate() }
        let row = taskRow(named: "URL train", app: app)
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        XCTAssertTrue(app.tabBars.buttons["All"].isSelected)
        XCTAssertTrue(app.buttons["New task"].exists)
        XCTAssertFalse(app.textFields["task-description"].exists)
        XCTAssertFalse(app.buttons["task-url-back"].exists)
        capture("URL-created task appears as a normal row in the current list", app)
        row.tap()
        let description = app.textFields["task-description"]
        XCTAssertTrue(description.waitForExistence(timeout: 10))
        XCTAssertEqual(description.value as? String, "URL train")
        XCTAssertTrue(app.buttons["row-scheduled"].exists)
        XCTAssertTrue(app.buttons["row-deadline"].exists)
        XCTAssertTrue(app.buttons["row-waiting-date"].exists)
        capture("URL-created task uses the ordinary row editor when tapped", app)
        app.terminate()
        app.launch()
        selectAllTasks(app)
        XCTAssertTrue(taskRow(named: "URL train", app: app).waitForExistence(timeout: 15))
    }

    func testActualCallbackDeliveryPreservesArgumentsAndDurableUUIDResultAndReportsInvalidInput() throws {
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launch()
        selectAllTasks(app)
        defer { app.terminate() }
        let host = try send(try actionURL(description: "Callback café & +", extra: []))
        defer { host.terminate() }
        let success = try callback(host)
        XCTAssertEqual(success["savedLocally"] as? Bool, true)
        let task = try XCTUnwrap(success["task"] as? [String: Any])
        let id = try XCTUnwrap(task["uuid"] as? String)
        XCTAssertNotNil(UUID(uuidString: id))
        XCTAssertEqual(task["description"] as? String, "Callback café & +")
        XCTAssertTrue(task["scheduled"] is NSNull)
        XCTAssertEqual(task["openTaskURL"] as? String, "tsk://open-task?id=" + id)
        capture("Actual caller receives structured success callback", host)
        host.terminate()
        _ = try send(try actionURL(description: "Rejected URL task", extra: [URLQueryItem(name: "scheduled", value: "2026-11-05")]))
        let failure = try callback(host)
        XCTAssertEqual(failure["savedLocally"] as? Bool, false)
        XCTAssertEqual(failure["success"] as? Bool, false)
        capture("Actual caller receives validation error callback", host)
        host.terminate()
        app.terminate()
        app.launch()
        selectAllTasks(app)
        XCTAssertTrue(app.buttons["task-" + id].waitForExistence(timeout: 15))
        XCTAssertFalse(taskRow(named: "Rejected URL task", app: app).exists)
        _ = try send(try XCTUnwrap(task["openTaskURL"] as? String))
        XCTAssertTrue(app.textFields["task-description"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.textFields["task-description"].value as? String, "Callback café & +")
    }

    func testURLSavesValidDraftAndRetainsInvalidDraftWithoutCreatingTask() throws {
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_INTENT_DESCRIPTION"] = "Before URL draft"
        app.launch()
        selectAllTasks(app)
        defer { app.terminate() }
        taskRow(named: "Before URL draft", app: app).tap()
        let title = app.textFields["task-description"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        replaceTaskText(title, with: "Saved before URL", app: app)
        let host = try send("tsk://add?description=After%20valid%20draft")
        defer { host.terminate() }
        XCTAssertTrue(taskRow(named: "After valid draft", app: app).waitForExistence(timeout: 15))
        XCTAssertFalse(title.exists)
        XCTAssertFalse(app.buttons["task-url-back"].exists)
        XCTAssertTrue(taskRow(named: "Saved before URL", app: app).waitForExistence(timeout: 10))
        taskRow(named: "Saved before URL", app: app).tap()
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        replaceTaskText(title, with: "", app: app)
        capture("Current invalid draft before URL navigation", app)
        host.terminate()
        _ = try send("tsk://add?description=Must%20not%20exist")
        XCTAssertTrue(app.alerts["Task action"].waitForExistence(timeout: 15))
        app.alerts.buttons["OK"].tap()
        let retained = title.waitForExistence(timeout: 5)
        capture("Current draft after URL error dismissal", app)
        if !retained {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Draft retention failure hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertTrue(retained)
        XCTAssertEqual(title.value as? String, "")
        XCTAssertTrue(app.staticTexts["draft-error"].exists)
        XCTAssertFalse(app.buttons["task-url-back"].exists)
        capture("Invalid current draft remains editable after rejected URL navigation", app)
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "TSK_TEST_INTENT_DESCRIPTION")
        app.launch()
        selectAllTasks(app)
        XCTAssertFalse(taskRow(named: "Must not exist", app: app).exists)
        XCTAssertTrue(taskRow(named: "Saved before URL", app: app).waitForExistence(timeout: 15))
        app.buttons["New task"].tap()
        let captureDraft = app.textFields["task-description"]
        XCTAssertTrue(captureDraft.waitForExistence(timeout: 10))
        host.terminate()
        _ = try send("tsk://add?description=Rejected%20capture%20navigation")
        XCTAssertTrue(app.alerts["Task action"].waitForExistence(timeout: 15))
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(captureDraft.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["save-task"].exists)
        XCTAssertTrue(app.staticTexts["draft-error"].exists)
        capture("Invalid capture draft survives rejected URL navigation", app)
        captureDraft.tap()
        captureDraft.typeText("Capture before URL")
        host.terminate()
        _ = try send("tsk://add?description=After%20capture")
        XCTAssertTrue(taskRow(named: "After capture", app: app).waitForExistence(timeout: 15))
        XCTAssertFalse(captureDraft.exists)
        XCTAssertFalse(app.buttons["task-url-back"].exists)
        XCTAssertTrue(taskRow(named: "Capture before URL", app: app).waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        selectAllTasks(app)
        XCTAssertFalse(taskRow(named: "Rejected capture navigation", app: app).exists)
        XCTAssertTrue(taskRow(named: "After capture", app: app).waitForExistence(timeout: 10))
    }

    func testOversizedResultAndFailedDeliveryKeepExactlyOneDurableTaskPerAdd() throws {
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launch()
        selectAllTasks(app)
        defer { app.terminate() }
        let url = try actionURL(description: "Oversized callback", extra: [URLQueryItem(name: "project", value: String(repeating: "é", count: 2000))])
        let host = try send(url)
        defer { host.terminate() }
        let result = try callback(host)
        XCTAssertEqual(result["savedLocally"] as? Bool, true)
        let error = try XCTUnwrap(result["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? String, "result_too_large")
        let id = try XCTUnwrap(result["uuid"] as? String)
        host.terminate()
        _ = try send("tsk://add?description=Undeliverable%20callback&x-success=tsk-unregistered-fixture%3A%2F%2Fdone")
        XCTAssertTrue(app.alerts["Task action"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.alerts.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "saved locally")).firstMatch.exists)
        capture("Failed callback delivery reports durable local success", app)
        app.alerts.buttons["OK"].tap()
        app.terminate()
        app.launch()
        selectAllTasks(app)
        XCTAssertTrue(app.buttons["task-" + id].waitForExistence(timeout: 15))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "task-", "Oversized callback")).count, 1)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "task-", "Undeliverable callback")).count, 1)
    }

    private func send(_ url: String) throws -> XCUIApplication {
        let host = XCUIApplication(bundleIdentifier: "com.julesseguin.tsk.sharefixture")
        host.launchEnvironment["TSK_ACTION_FIXTURE_URL"] = url
        host.launch()
        let open = host.buttons["action-fixture-open"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        return host
    }

    private func actionURL(description: String, extra: [URLQueryItem]) throws -> String {
        var components = URLComponents(string: "tsk://add")!
        components.queryItems = [URLQueryItem(name: "description", value: description), URLQueryItem(name: "x-success", value: "tsk-action-fixture://done?token=a%2Bb&token=second"), URLQueryItem(name: "x-error", value: "tsk-action-fixture://error?token=a%2Bb&token=second")] + extra
        return try XCTUnwrap(components.url?.absoluteString)
    }

    private func callback(_ host: XCUIApplication) throws -> [String: Any] {
        let output = host.staticTexts["action-fixture-callback"]
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in output.exists && output.label != "No callback" }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 20), .completed)
        let url = try XCTUnwrap(URLComponents(string: output.label))
        XCTAssertEqual(url.queryItems?.filter { $0.name == "token" }.map(\.value), ["a+b", "second"])
        let result = try XCTUnwrap(url.queryItems?.first { $0.name == "result" }?.value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any])
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
