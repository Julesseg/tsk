import XCTest

@MainActor final class TaskNavigationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testInstalledOpenTaskURLUsesFreshRecordExpandsContainingListAndReturnsWithColdMissingIdentity() throws {
        let app = fixture()
        app.launch()
        selectAllTasks(app)
        let row = taskRow(named: "Navigation task", app: app)
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        let id = String(row.identifier.dropFirst(5))
        app.tabBars.buttons["Today"].tap()
        capture("Before external task navigation in Today", app)
        let host = try send("tsk://open-task?id=" + id)
        defer { host.terminate(); app.terminate() }
        let title = app.textFields["task-description"]
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        XCTAssertEqual(title.value as? String, "Navigation task")
        XCTAssertTrue(taskRow(named: "Second task", app: app).exists)
        capture("After warm URL containing list with exactly one expanded task", app)
        replaceTaskText(title, with: "Fresh navigation task", app: app)
        app.buttons["back-from-task-action"].tap()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Today"].isSelected)
        _ = try send("tsk://open-task?id=" + id)
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertEqual(title.value as? String, "Fresh navigation task")
        capture("After warm URL freshly resolved task", app)
        app.buttons["back-from-task-action"].tap()
        selectDoneTasks(app)
        let completed = taskRow(named: "Completed navigation task", app: app)
        XCTAssertTrue(completed.waitForExistence(timeout: 10))
        let completedID = String(completed.identifier.dropFirst(5))
        _ = try send("tsk://open-task?id=" + completedID)
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertEqual(title.value as? String, "Completed navigation task")
        capture("Completed task expanded in Done", app)
        app.terminate()
        _ = try send("tsk://open-task?id=" + UUID().uuidString)
        XCTAssertTrue(app.alerts["Task action"].waitForExistence(timeout: 15))
        capture("Missing task identity reports clear error", app)
        app.alerts.buttons["OK"].tap()
        XCTAssertFalse(app.buttons["back-from-task-action"].exists)
    }

    func testInstalledOpenViewURLsReachHiddenViewsExactProjectAndRenamedSavedViewWithoutChangingFavorites() throws {
        let app = fixture()
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 15))
        let originalTabs = app.tabBars.buttons.allElementsBoundByIndex.map(\.label)
        capture("Before navigation favorite tabs", app)
        for (argument, title) in [("today", "Today"), ("upcoming", "Upcoming"), ("unfinished", "All unfinished"), ("done", "Done"), ("projects", "Projects"), ("project&project=Work.Travel", "Work.Travel")] {
            _ = try send("tsk://open-view?view=" + argument)
            XCTAssertTrue(app.buttons["back-from-task-action"].waitForExistence(timeout: 15))
            XCTAssertTrue(app.navigationBars[title].exists)
            capture("Open view " + title, app)
            app.buttons["back-from-task-action"].tap()
            XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.tabBars.buttons.allElementsBoundByIndex.map(\.label), originalTabs)
        }
        app.tabBars.buttons["Projects"].tap()
        app.buttons["project-Work.Travel"].tap()
        XCTAssertTrue(app.navigationBars["Work.Travel"].waitForExistence(timeout: 10))
        _ = try send("tsk://open-view?view=done")
        XCTAssertTrue(app.navigationBars["Done"].waitForExistence(timeout: 15))
        app.buttons["back-from-task-action"].tap()
        XCTAssertTrue(app.navigationBars["Work.Travel"].waitForExistence(timeout: 10))
        XCTAssertTrue(taskRow(named: "Navigation task", app: app).exists)
        capture("Back restores originating project breadcrumb", app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        openWorkspaceSetting("custom-views", app: app)
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "saved-view-")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        let id = String(saved.identifier.dropFirst("saved-view-".count))
        app.terminate()
        app.launchEnvironment["TSK_TEST_NAVIGATION_VIEW_NAME"] = "Renamed navigation view"
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 15))
        _ = try send("tsk://open-view?view=saved&id=" + id)
        XCTAssertTrue(app.navigationBars["Renamed navigation view"].waitForExistence(timeout: 15))
        XCTAssertTrue(taskRow(named: "Navigation task", app: app).exists)
        capture("Stable UUID opens renamed hidden saved view", app)
        app.buttons["back-from-task-action"].tap()
        XCTAssertEqual(app.tabBars.buttons.allElementsBoundByIndex.map(\.label), originalTabs)
        app.terminate()
        app.launchEnvironment["TSK_TEST_NAVIGATION_DELETE_VIEW"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 15))
        _ = try send("tsk://open-view?view=saved&id=" + id)
        XCTAssertTrue(app.alerts["Task action"].waitForExistence(timeout: 15))
        capture("Missing saved view preserves workspace and favorites", app)
        app.alerts.buttons["OK"].tap()
        XCTAssertEqual(app.tabBars.buttons.allElementsBoundByIndex.map(\.label), originalTabs)
        app.terminate()
    }

    func testNavigationCallbacksReportActualDraftFailureAndSuccessfulDestination() throws {
        let app = fixture()
        app.launch()
        selectAllTasks(app)
        taskRow(named: "Navigation task", app: app).tap()
        let title = app.textFields["task-description"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        replaceTaskText(title, with: " ", app: app)
        capture("Before navigation invalid draft", app)
        let request = "tsk://open-view?view=done&x-success=tsk-action-fixture%3A%2F%2Fdone&x-error=tsk-action-fixture%3A%2F%2Ferror"
        let host = try send(request)
        let failure = try callback(host)
        XCTAssertEqual(failure["success"] as? Bool, false)
        let error = try XCTUnwrap(failure["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? String, "navigation_error")
        app.activate()
        XCTAssertEqual(title.value as? String, " ")
        XCTAssertFalse(app.buttons["back-from-task-action"].exists)
        capture("After failed navigation draft retained", app)
        replaceTaskText(title, with: "Saved before Open View", app: app)
        host.terminate()
        _ = try send(request)
        let success = try callback(host)
        XCTAssertEqual(success["navigated"] as? Bool, true)
        XCTAssertEqual(success["title"] as? String, "Done")
        app.activate()
        XCTAssertTrue(app.navigationBars["Done"].waitForExistence(timeout: 10))
        capture("Actual success callback follows Done navigation", app)
        app.buttons["back-from-task-action"].tap()
        XCTAssertTrue(taskRow(named: "Saved before Open View", app: app).waitForExistence(timeout: 10))
        host.terminate()
        app.terminate()
    }

    private func fixture() -> XCUIApplication {
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_NAVIGATION_FIXTURE"] = "1"
        return app
    }

    private func send(_ url: String) throws -> XCUIApplication {
        let host = XCUIApplication(bundleIdentifier: "com.julesseguin.tsk.sharefixture")
        host.launchEnvironment["TSK_ACTION_FIXTURE_URL"] = url
        host.launch()
        let button = host.buttons["action-fixture-open"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
        return host
    }

    private func callback(_ host: XCUIApplication) throws -> [String: Any] {
        let output = host.staticTexts["action-fixture-callback"]
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in output.exists && output.label != "No callback" }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 20), .completed)
        let url = try XCTUnwrap(URLComponents(string: output.label))
        let json = try XCTUnwrap(url.queryItems?.first { $0.name == "result" }?.value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
