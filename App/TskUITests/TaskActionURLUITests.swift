import XCTest

@MainActor final class TaskActionURLUITests: XCTestCase {
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

    func testSystemFindURLShowsCombinedResultsAndEmptyStateWithoutChangingWorkspace() throws {
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launch()
        selectAllTasks(app)
        defer { app.terminate() }
        let host = try send("tsk://add?description=Find%20TRAIN&project=Travel&tags=rail&tags=trip&priority=H&scheduled=2026-11-05T08:30:00Z&deadline=2026-11-06T08:30:00Z&waiting-until=2026-11-04T08:30:00Z")
        defer { host.terminate() }
        XCTAssertTrue(taskRow(named: "Find TRAIN", app: app).waitForExistence(timeout: 20))
        host.terminate()
        _ = try send("tsk://add?description=Find%20child&project=Travel.Rail&tags=rail&tags=trip&priority=H")
        XCTAssertTrue(taskRow(named: "Find child", app: app).waitForExistence(timeout: 15))
        host.terminate()
        _ = try send("tsk://find?description=train&project=Travel&tags=rail&tags=trip&priority=H&scheduled-from=2026-11-05T08:30:00Z&scheduled-through=2026-11-05T08:30:00Z&deadline-from=2026-11-06T08:30:00Z&waiting-until-through=2026-11-04T08:30:00Z")
        XCTAssertTrue(app.collectionViews["find-results-list"].waitForExistence(timeout: 15))
        let matches = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "find-task-"))
        XCTAssertEqual(matches.count, 1)
        XCTAssertTrue(matches.firstMatch.label.contains("Find TRAIN"))
        capture("Find URL combined filters show only the exact matching saved task", app)
        matches.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["task-detail-description"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["task-detail-description"].label, "Find TRAIN")
        app.navigationBars.buttons["Find Tasks"].tap()
        app.buttons["close-find-results"].tap()
        XCTAssertTrue(app.tabBars.buttons["All"].isSelected)
        host.terminate()
        _ = try send("tsk://find?description=No%20such%20task")
        XCTAssertTrue(app.otherElements["find-results-empty"].waitForExistence(timeout: 15))
        capture("Find URL successful empty state", app)
        app.buttons["close-find-results"].tap()
        XCTAssertTrue(app.tabBars.buttons["All"].isSelected)
        XCTAssertTrue(taskRow(named: "Find child", app: app).exists)
        app.terminate()
        app.launch()
        selectAllTasks(app)
        XCTAssertFalse(app.buttons["close-find-results"].exists)
        XCTAssertTrue(taskRow(named: "Find TRAIN", app: app).waitForExistence(timeout: 15))
        app.buttons["workspace-settings"].tap()
        XCTAssertTrue(app.buttons["close-workspace-settings"].waitForExistence(timeout: 10))
        host.terminate()
        _ = try send("tsk://find")
        XCTAssertTrue(app.alerts["Task action"].waitForExistence(timeout: 15))
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.buttons["close-workspace-settings"].exists)
        app.buttons["close-workspace-settings"].tap()
    }

    func testSystemFindCallbackReturnsRichPagesEmptyListsAndExplicitOversizeFailure() throws {
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launch()
        selectAllTasks(app)
        defer { app.terminate() }
        let host = try send(try actionURL(description: "Find callback A", extra: [URLQueryItem(name: "project", value: "Travel"), URLQueryItem(name: "tags", value: "rail")]))
        defer { host.terminate() }
        let created = try callback(host)
        let first = try XCTUnwrap(created["task"] as? [String: Any])
        let firstID = try XCTUnwrap(first["uuid"] as? String)
        host.terminate()
        _ = try send(try actionURL(description: "Find callback B", extra: [URLQueryItem(name: "project", value: String(repeating: "é", count: 2000))]))
        _ = try callback(host)
        func findURL(_ query: [URLQueryItem]) throws -> String {
            var url = URLComponents(string: "tsk://find")!
            url.queryItems = query + [URLQueryItem(name: "x-success", value: "tsk-action-fixture://done?token=a%2Bb&token=second")]
            return try XCTUnwrap(url.url?.absoluteString)
        }
        host.terminate()
        _ = try send(try findURL([URLQueryItem(name: "description", value: "Find callback"), URLQueryItem(name: "sort", value: "description-asc"), URLQueryItem(name: "limit", value: "1")]))
        let page = try callback(host)
        let tasks = try XCTUnwrap(page["tasks"] as? [[String: Any]])
        XCTAssertEqual(page["success"] as? Bool, true)
        XCTAssertNil(page["savedLocally"])
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.first?["uuid"] as? String, firstID)
        XCTAssertEqual(tasks.first?["tags"] as? [String], ["rail"])
        XCTAssertTrue(tasks.first?["scheduled"] is NSNull)
        capture("Actual Find callback returns a rich UUID-bearing task page", host)
        host.terminate()
        _ = try send(try findURL([URLQueryItem(name: "offset", value: "2")]))
        let empty = try callback(host)
        XCTAssertEqual((empty["tasks"] as? [[String: Any]])?.count, 0)
        host.terminate()
        _ = try send(try findURL([]))
        let oversized = try callback(host)
        XCTAssertEqual(oversized["success"] as? Bool, false)
        XCTAssertEqual((oversized["error"] as? [String: Any])?["code"] as? String, "result_too_large")
        XCTAssertNil(oversized["tasks"])
        capture("Find callback explicitly rejects an oversized result without truncation", host)
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
