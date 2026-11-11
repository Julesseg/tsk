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

    func testCompleteURLReturnsRichSavedTaskRevealsItAndProtectsNestedDrafts() throws {
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launch()
        selectAllTasks(app)
        defer { app.terminate() }
        let host = try send(try actionURL(description: "Complete URL train", extra: [
            URLQueryItem(name: "project", value: "Travel"), URLQueryItem(name: "tags", value: "trip"),
            URLQueryItem(name: "priority", value: "H"), URLQueryItem(name: "scheduled", value: "2026-11-05T08:30:00Z"),
            URLQueryItem(name: "deadline", value: "2026-11-06T08:00:00Z"), URLQueryItem(name: "waiting-until", value: "2026-11-04T09:00:00Z")
        ]))
        defer { host.terminate() }
        let added = try XCTUnwrap(try callback(host)["task"] as? [String: Any])
        let id = try XCTUnwrap(added["uuid"] as? String)
        host.terminate()
        _ = try send(try completionURL(id: id))
        let result = try callback(host)
        XCTAssertEqual(result["savedLocally"] as? Bool, true)
        let completed = try XCTUnwrap(result["task"] as? [String: Any])
        XCTAssertEqual(completed["status"] as? String, "completed")
        for key in ["uuid", "description", "project", "tags", "priority", "scheduled", "deadline", "waitingUntil", "openTaskURL"] {
            XCTAssertEqual(completed[key] as? NSObject, added[key] as? NSObject, key)
        }
        capture("Installed caller receives rich saved completion", host)
        host.terminate()
        _ = try send(try completionURL(id: id))
        XCTAssertEqual(try callback(host)["task"] as? NSDictionary, completed as NSDictionary)
        host.terminate()
        _ = try send("tsk://complete?id=" + id)
        let title = app.textFields["task-description"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertEqual(title.value as? String, "Complete URL train")
        XCTAssertTrue(app.buttons["back-from-linked-task"].exists)
        capture("Completed task expands in its containing list", app)
        host.terminate()
        _ = try send("tsk://complete?id=" + id)
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        replaceTaskText(title, with: " ", app: app)
        host.terminate()
        _ = try send(try completionURL(id: id))
        let failure = try callback(host)
        XCTAssertEqual((failure["error"] as? [String: Any])?["code"] as? String, "navigation_error")
        XCTAssertEqual(failure["savedLocally"] as? Bool, false)
        host.terminate()
        _ = try send("tsk://open-task?id=" + id)
        XCTAssertTrue(app.alerts["Task action"].waitForExistence(timeout: 15))
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(title.exists)
        XCTAssertEqual(title.value as? String, " ")
        capture("Invalid nested draft remains after rejected completion", app)
        replaceTaskText(title, with: "Must stay unsaved for missing target", app: app)
        host.terminate()
        _ = try send(try completionURL(id: UUID().uuidString))
        let missing = try callback(host)
        XCTAssertEqual((missing["error"] as? [String: Any])?["code"] as? String, "task_not_found")
        app.terminate()
        app.launch()
        selectDoneTasks(app)
        XCTAssertTrue(taskRow(named: "Complete URL train", app: app).waitForExistence(timeout: 15))
        XCTAssertFalse(taskRow(named: "Must stay unsaved for missing target", app: app).exists)
        host.terminate()
        _ = try send("tsk://complete?id=" + id)
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        replaceTaskText(title, with: "Saved before repeated completion", app: app)
        host.terminate()
        _ = try send(try completionURL(id: id, callback: "tsk-unregistered-fixture://done"))
        XCTAssertTrue(app.alerts["Task action"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.alerts.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "saved locally")).firstMatch.exists)
        app.alerts.buttons["OK"].tap()
        app.terminate()
        app.launch()
        selectDoneTasks(app)
        XCTAssertTrue(app.buttons["task-" + id].waitForExistence(timeout: 15))
        XCTAssertTrue(taskRow(named: "Saved before repeated completion", app: app).exists)
    }

    func testCompleteOccurrenceURLPersistsAndMissingDeletedTargetsReturnErrors() throws {
        let parent = UUID().uuidString, child = UUID().uuidString, deleted = UUID().uuidString
        let records: [(id: String, attributes: [String: String])] = [
            (parent, ["status": "recurring", "description": "URL series", "mask": "-", "recur": "weekly"]),
            (child, ["status": "pending", "description": "URL occurrence", "parent": parent, "imask": "0", "due": "1793952000", "scheduled": "1793867400", "start": "1793800000"]),
            (deleted, ["status": "deleted", "description": "Deleted URL target"])
        ]
        let encodedRecords: [[String: Any]] = records.map { record in
            ["id": record.id, "attributes": record.attributes.map { ["key": $0.key, "value": $0.value] }]
        }
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_RECORDED_RECURRENCE"] = String(decoding: try JSONSerialization.data(withJSONObject: encodedRecords), as: UTF8.self)
        app.launch()
        selectAllTasks(app)
        defer { app.terminate() }
        let host = try send(try completionURL(id: child))
        defer { host.terminate() }
        let task = try XCTUnwrap(try callback(host)["task"] as? [String: Any])
        XCTAssertEqual(task["uuid"] as? String, child)
        XCTAssertEqual(task["status"] as? String, "completed")
        XCTAssertEqual(task["scheduled"] as? String, "2026-11-05T08:30:00Z")
        XCTAssertEqual(task["deadline"] as? String, "2026-11-06T08:00:00Z")
        host.terminate()
        _ = try send("tsk://complete?id=" + child)
        XCTAssertTrue(app.staticTexts["task-detail-description"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["task-detail-description"].label, "URL occurrence")
        XCTAssertFalse(app.buttons["complete-task"].exists)
        capture("Completed occurrence opens preserved read-only information", app)
        for (id, code) in [(UUID().uuidString, "task_not_found"), (deleted, "task_deleted"), ("1", "invalid_input")] {
            host.terminate()
            _ = try send(try completionURL(id: id))
            let failure = try callback(host)
            XCTAssertEqual(failure["savedLocally"] as? Bool, false)
            XCTAssertEqual((failure["error"] as? [String: Any])?["code"] as? String, code)
        }
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "TSK_TEST_RECORDED_RECURRENCE")
        app.launch()
        selectDoneTasks(app)
        XCTAssertTrue(app.buttons["task-" + child].waitForExistence(timeout: 15))
    }

    private func completionURL(id: String, callback: String = "tsk-action-fixture://done?token=a%2Bb&token=second") throws -> String {
        var url = URLComponents(string: "tsk://complete")!
        url.queryItems = [URLQueryItem(name: "id", value: id), URLQueryItem(name: "x-success", value: callback), URLQueryItem(name: "x-error", value: callback)]
        return try XCTUnwrap(url.url?.absoluteString)
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
