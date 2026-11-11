import XCTest

@MainActor final class TaskAddURLUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

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
        app.activate()
        XCTAssertTrue(app.buttons["task-" + id].waitForExistence(timeout: 15))
        XCTAssertTrue(app.tabBars.buttons["All"].isSelected)
        XCTAssertFalse(app.textFields["task-description"].exists)
        XCTAssertFalse(app.buttons["task-url-back"].exists)
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
        let invalidDescription = "   "
        replaceTaskText(title, with: invalidDescription, app: app)
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
        XCTAssertEqual(title.value as? String, invalidDescription)
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
        captureDraft.typeText("Capture before URL")
        openTaskRowParameter("tags", app: app)
        let tagInput = app.textFields["row-tag-input"]
        XCTAssertTrue(tagInput.waitForExistence(timeout: 5))
        tagInput.tap()
        tagInput.typeText("bad tag")
        host.terminate()
        _ = try send("tsk://add?description=Rejected%20capture%20navigation")
        XCTAssertTrue(app.alerts["Task action"].waitForExistence(timeout: 15))
        capture("URL navigation error above the retained invalid capture tag picker", app)
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(captureDraft.waitForExistence(timeout: 5))
        XCTAssertEqual(captureDraft.value as? String, "Capture before URL")
        XCTAssertEqual(tagInput.value as? String, "bad tag")
        XCTAssertTrue(app.buttons["collapse-task-row"].exists)
        XCTAssertTrue(app.staticTexts["draft-error"].exists)
        capture("Invalid capture draft survives rejected URL navigation", app)
        replaceTaskText(tagInput, with: "trip", app: app)
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

    func testModifySystemURLSavesAllFieldsTagModesClearsAndAtomicRejections() throws {
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launch()
        selectAllTasks(app)
        defer { app.terminate() }
        let host = try send(try actionURL(description: "Modify original", extra: []))
        defer { host.terminate() }
        let created = try XCTUnwrap(try callback(host)["task"] as? [String: Any])
        let id = try XCTUnwrap(created["uuid"] as? String)
        func modify(_ items: [URLQueryItem]) throws -> [String: Any] {
            host.terminate()
            var url = URLComponents(string: "tsk://modify")!
            url.queryItems = [URLQueryItem(name: "id", value: id), URLQueryItem(name: "x-success", value: "tsk-action-fixture://done?token=a%2Bb&token=second"), URLQueryItem(name: "x-error", value: "tsk-action-fixture://error?token=a%2Bb&token=second")] + items
            _ = try send(try XCTUnwrap(url.url?.absoluteString))
            return try callback(host)
        }
        let changes = [URLQueryItem(name: "description", value: "Modified timed task"), URLQueryItem(name: "project", value: "Travel"), URLQueryItem(name: "priority", value: "H"), URLQueryItem(name: "tags", value: "café"), URLQueryItem(name: "tags", value: "cafe\u{301}"), URLQueryItem(name: "scheduled", value: "2026-11-05T08:30:30Z"), URLQueryItem(name: "deadline", value: "2026-11-06T09:45:00Z"), URLQueryItem(name: "waiting-until", value: "2026-11-04T07:15:00Z")]
        let result = try modify(changes)
        XCTAssertEqual(result["savedLocally"] as? Bool, true)
        let task = try XCTUnwrap(result["task"] as? [String: Any])
        XCTAssertEqual(task["uuid"] as? String, id)
        XCTAssertEqual(task["scheduled"] as? String, "2026-11-05T08:30:30Z")
        XCTAssertEqual(task["deadline"] as? String, "2026-11-06T09:45:00Z")
        XCTAssertEqual(task["waitingUntil"] as? String, "2026-11-04T07:15:00Z")
        capture("Modify delivered all timed fields through the installed URL callback", host)
        let omitted = try XCTUnwrap(try modify([])["task"] as? [String: Any])
        XCTAssertEqual(omitted["project"] as? String, "Travel")
        XCTAssertEqual(omitted["priority"] as? String, "H")
        XCTAssertEqual(omitted["scheduled"] as? String, "2026-11-05T08:30:30Z")
        let removed = try XCTUnwrap(try modify([URLQueryItem(name: "tags", value: "café"), URLQueryItem(name: "tag-operation", value: "remove")])["task"] as? [String: Any])
        XCTAssertEqual((removed["tags"] as? [String])?.map { Array($0.utf8) }, [Array("cafe\u{301}".utf8)])
        let replaced = try XCTUnwrap(try modify([URLQueryItem(name: "tags", value: "rail"), URLQueryItem(name: "tag-operation", value: "replace")])["task"] as? [String: Any])
        XCTAssertEqual(replaced["tags"] as? [String], ["rail"])
        let rejected = try modify([URLQueryItem(name: "description", value: "Must not save"), URLQueryItem(name: "priority", value: "H"), URLQueryItem(name: "clear-priority", value: "true")])
        XCTAssertEqual(rejected["savedLocally"] as? Bool, false)
        let retained = try XCTUnwrap(try modify([])["task"] as? [String: Any])
        XCTAssertEqual(retained["description"] as? String, "Modified timed task")
        let cleared = try XCTUnwrap(try modify([URLQueryItem(name: "tag-operation", value: "clear")] + ["project", "priority", "scheduled", "deadline", "waiting-until"].map { URLQueryItem(name: "clear-" + $0, value: "true") })["task"] as? [String: Any])
        for key in ["project", "priority", "scheduled", "deadline", "waitingUntil"] { XCTAssertTrue(cleared[key] is NSNull) }
        XCTAssertEqual(cleared["tags"] as? [String], [])
        host.terminate()
        app.terminate()
        app.launch()
        selectAllTasks(app)
        XCTAssertTrue(taskRow(named: "Modified timed task", app: app).waitForExistence(timeout: 15))
        XCTAssertFalse(taskRow(named: "Must not save", app: app).exists)
        capture("Modified task retains identity and survives relaunch after explicit clearing", app)
    }

    func testModifyURLSettlesActiveEditingRevealsTimedResultAndPreservesInvalidDraft() throws {
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_INTENT_DESCRIPTION"] = "Before Modify"
        app.launch()
        selectAllTasks(app)
        defer { app.terminate() }
        let row = taskRow(named: "Before Modify", app: app)
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        let id = try XCTUnwrap(UUID(uuidString: String(row.identifier.dropFirst(5)))).uuidString
        row.tap()
        let title = app.textFields["task-description"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        replaceTaskText(title, with: "Draft saved before Modify", app: app)
        let host = try send("tsk://modify?id=\(id)&scheduled=2026-11-05T08:30:30Z&deadline=2026-11-06T09:45:00Z&waiting-until=2026-11-04T07:15:00Z")
        defer { host.terminate() }
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertEqual(title.value as? String, "Draft saved before Modify")
        XCTAssertTrue(app.buttons["row-scheduled"].exists && app.buttons["row-deadline"].exists && app.buttons["row-waiting-date"].exists)
        capture("Modify reveals the saved task with independent timed dates after settling an active edit", app)
        replaceTaskText(title, with: "   ", app: app)
        host.terminate()
        _ = try send("tsk://modify?id=\(id)&description=Must%20not%20save")
        XCTAssertTrue(app.alerts["Task action"].waitForExistence(timeout: 15))
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "   ")
        XCTAssertTrue(app.staticTexts["draft-error"].exists)
        capture("Invalid active draft remains editable after rejected Modify navigation", app)
        replaceTaskText(title, with: "Draft saved before Modify", app: app)
        app.buttons["task-row-information"].tap()
        XCTAssertTrue(app.buttons["edit-task"].waitForExistence(timeout: 10))
        app.buttons["edit-task"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        replaceTaskText(title, with: "   ", app: app)
        host.terminate()
        _ = try send("tsk://modify?id=\(id)&description=Must%20not%20save")
        XCTAssertTrue(app.alerts["Task action"].waitForExistence(timeout: 15))
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "   ")
        XCTAssertTrue(app.staticTexts["draft-error"].exists)
        capture("Invalid nested Edit sheet remains after rejected Modify navigation", app)
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "TSK_TEST_INTENT_DESCRIPTION")
        app.launch()
        selectAllTasks(app)
        XCTAssertTrue(taskRow(named: "Draft saved before Modify", app: app).waitForExistence(timeout: 15))
        XCTAssertFalse(taskRow(named: "Must not save", app: app).exists)
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
