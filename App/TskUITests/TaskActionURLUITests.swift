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
        let emptyTitle = app.staticTexts.matching(identifier: "find-results-empty").matching(NSPredicate(format: "label == %@", "No matching tasks")).firstMatch
        XCTAssertTrue(emptyTitle.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["No saved tasks match the supplied filters."].exists)
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

    func testSystemDeleteCallbackReturnsDurableDeletedResultAndRejectsSubsequentOpen() throws {
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launch()
        selectAllTasks(app)
        defer { app.terminate() }
        let host = try send(try actionURL(description: "Delete callback", extra: [URLQueryItem(name: "project", value: "Travel"), URLQueryItem(name: "tags", value: "trip")]))
        defer { host.terminate() }
        let created = try callback(host)
        let task = try XCTUnwrap(created["task"] as? [String: Any])
        let id = try XCTUnwrap(task["uuid"] as? String)
        host.terminate()
        _ = try send("tsk://find?description=Delete%20callback&status=all")
        XCTAssertTrue(app.buttons["find-task-" + id].waitForExistence(timeout: 15))
        let url = "tsk://delete?id=" + id + "&x-success=tsk-action-fixture%3A%2F%2Fdone%3Ftoken%3Da%252Bb%26token%3Dsecond"
        for _ in 0..<2 {
            host.terminate()
            _ = try send(url)
            let result = try callback(host)
            XCTAssertEqual(result["success"] as? Bool, true)
            XCTAssertEqual(result["savedLocally"] as? Bool, true)
            let deleted = try XCTUnwrap(result["task"] as? [String: Any])
            XCTAssertEqual(deleted["uuid"] as? String, id)
            XCTAssertEqual(deleted["status"] as? String, "deleted")
            XCTAssertEqual(deleted["project"] as? String, "Travel")
            XCTAssertEqual(deleted["tags"] as? [String], ["trip"])
        }
        capture("Installed caller receives idempotent durable deletion result", host)
        app.activate()
        XCTAssertTrue(app.staticTexts["No matching tasks"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["find-task-" + id].exists)
        capture("Existing Find results remove a task after URL deletion", app)
        app.buttons["close-find-results"].tap()
        host.terminate()
        _ = try send("tsk://find?status=all&description=Delete%20callback&x-success=tsk-action-fixture%3A%2F%2Fdone%3Ftoken%3Da%252Bb%26token%3Dsecond")
        let found = try callback(host)
        XCTAssertEqual((found["tasks"] as? [[String: Any]])?.count, 0)
        host.terminate()
        _ = try send("tsk://open-task?id=" + id)
        XCTAssertTrue(app.alerts["Task action"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.alerts.staticTexts["This task is no longer available."].exists)
        app.alerts.buttons["OK"].tap()
        XCTAssertFalse(app.textFields["task-description"].exists)
        app.terminate()
        app.launch()
        selectAllTasks(app)
        XCTAssertFalse(taskRow(named: "Delete callback", app: app).exists)
    }

    func testSystemDeletePreservesInvalidLinkedDraftThenConfirmsWithoutOpeningDeletedEditor() throws {
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launch()
        selectAllTasks(app)
        defer { app.terminate() }
        let host = try send(try actionURL(description: "Delete after draft", extra: []))
        defer { host.terminate() }
        let created = try callback(host)
        let id = try XCTUnwrap((created["task"] as? [String: Any])?["uuid"] as? String)
        host.terminate()
        _ = try send("tsk://open-task?id=" + id)
        let title = app.textFields["task-description"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        replaceTaskText(title, with: "   ", app: app)
        host.terminate()
        _ = try send("tsk://delete?id=" + id)
        XCTAssertTrue(app.alerts["Task action"].waitForExistence(timeout: 15))
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "   ")
        replaceTaskText(title, with: "Saved before deletion", app: app)
        host.terminate()
        _ = try send("tsk://delete?id=" + id)
        XCTAssertTrue(app.alerts["Task action"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.alerts.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Deletion saved locally: Saved before deletion")).firstMatch.exists)
        capture("Delete URL confirms local success without opening deleted task", app)
        app.alerts.buttons["OK"].tap()
        XCTAssertFalse(title.exists)
        XCTAssertFalse(app.buttons["back-from-linked-task"].exists)
        XCTAssertFalse(app.staticTexts["task-detail-description"].exists)
        host.terminate()
        _ = try send("tsk://delete?id=" + UUID().uuidString)
        XCTAssertTrue(app.alerts["Task action"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.alerts.staticTexts["This task is no longer available."].exists)
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
        let host = XCUIApplication(bundleIdentifier: "com.julesseguin.tsk.actionfixture")
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
