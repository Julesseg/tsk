import XCTest

@MainActor
final class ReminderImportUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testRealEventKitCopyAndRecurrenceFixturePreserveSourcesAndDurableTasks() throws {
        XCTAssertEqual(ProcessInfo.processInfo.environment["TSK_UI_ISOLATED_SIMULATOR"], "1", "Run the real fixture only in the canonical disposable simulator lane.")
        let token = UUID().uuidString
        let app = taskTestApplication()
        resetOwnedReminderAuthorization(app, token: token, stage: "ordinary-before-launch")
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = token
        app.launchEnvironment["TSK_TEST_NOW"] = "1792144800"
        app.launchEnvironment["TSK_TEST_REMINDERS_FIXTURE"] = token
        app.launchEnvironment["TSK_UI_ISOLATED_SIMULATOR"] = "1"
        addTeardownBlock {
            app.terminate()
            app.launchEnvironment.removeValue(forKey: "TSK_TEST_REMINDERS_FIXTURE")
            app.launchEnvironment["TSK_TEST_REMINDERS_CLEANUP"] = token
            app.launch()
            XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20))
            app.terminate()
            self.resetOwnedReminderAuthorization(app, token: token, stage: "ordinary-after-cleanup")
        }
        app.launch()
        openImport(app)
        app.buttons["reminders-access"].tap()
        permission(allow: true)
        let listName = "tsk fixture \(token) selected"
        let list = app.descendants(matching: .any).matching(identifier: "reminders-list-" + listName).firstMatch
        XCTAssertTrue(revealTaskElement(list, in: "reminders-import-form", app: app), app.staticTexts["reminders-error"].label)
        setDateSwitch("reminders-list-" + listName, to: true, app: app, in: "reminders-import-form", keyboardDismissIdentifier: "dismiss-reminders-keyboard")
        let project = app.textFields["reminders-project-" + listName]
        XCTAssertTrue(revealTaskElement(project, in: "reminders-import-form", app: app))
        project.tap(); project.typeKey("a", modifierFlags: .command); project.typeText("Fixture.Reminders")
        tapTaskControlAtCenter(app.buttons["dismiss-reminders-keyboard"], app: app)
        XCTAssertTrue(revealTaskElement(app.buttons["reminders-preview"], in: "reminders-import-form", app: app))
        app.buttons["reminders-preview"].tap()
        XCTAssertTrue(app.staticTexts["reminders-preview-count"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.staticTexts["reminders-preview-count"].label, "2 eligible reminder(s)")
        capture("Actual EventKit selected-list preview and recurring exclusion", app)
        XCTAssertTrue(revealTaskElement(app.buttons["reminders-copy"], in: "reminders-import-form", app: app))
        app.buttons["reminders-copy"].tap()
        XCTAssertTrue(app.staticTexts["reminders-result"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.staticTexts["reminders-result"].label, "Copied 2; skipped 1; failed 0.")
        let report = app.descendants(matching: .any).matching(identifier: "reminders-fixture-report").firstMatch
        XCTAssertTrue(revealTaskElement(report, in: "reminders-import-form", app: app))
        let evidenceText = try XCTUnwrap(report.value as? String)
        XCTAssertTrue(evidenceText.contains("completionSequence"))
        XCTAssertTrue(evidenceText.contains("incompleteAfterRemoval"))
        XCTAssertTrue(evidenceText.contains("Verified four source reminders unchanged"))
        let attachment = XCTAttachment(string: evidenceText)
        attachment.name = "Real EventKit stored rules, five completions, removal scope and source preservation"
        attachment.lifetime = .keepAlways; add(attachment)
        capture("Copy result and real source preservation", app)
        XCTAssertTrue(revealTaskElement(app.buttons["reminders-view-tasks"], in: "reminders-import-form", app: app))
        app.buttons["reminders-view-tasks"].tap()
        XCTAssertTrue(taskRow(named: "Copy fixture H", app: app).waitForExistence(timeout: 15))
        XCTAssertTrue(taskRow(named: "Copy fixture none", app: app).exists)
        XCTAssertFalse(taskRow(named: "Exclude completed", app: app).exists)
        XCTAssertFalse(taskRow(named: "Exclude unselected", app: app).exists)
        XCTAssertFalse(taskRow(named: "Skip recurring", app: app).exists)
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "TSK_TEST_REMINDERS_FIXTURE")
        app.launch()
        selectAllTasks(app)
        XCTAssertTrue(taskRow(named: "Copy fixture H", app: app).waitForExistence(timeout: 15))
        openTaskInformation(taskRow(named: "Copy fixture H", app: app), app: app)
        let notes = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Fixture notes")).firstMatch
        XCTAssertTrue(revealTaskElement(notes, in: "task-detail-form", app: app))
        capture("Reopened durable task with copied notes and independent dates", app)
    }

    func testDeniedRealRemindersPermissionKeepsOrdinaryTaskWorkspaceUsable() {
        let app = taskTestApplication()
        app.resetAuthorizationStatus(for: .reminders)
        defer { app.terminate(); app.resetAuthorizationStatus(for: .reminders) }
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launch()
        openImport(app)
        app.buttons["reminders-access"].tap()
        permission(allow: false)
        XCTAssertTrue(app.staticTexts["reminders-error"].waitForExistence(timeout: 10))
        capture("Genuine denied Reminders permission", app)
        app.navigationBars.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 10))
        app.buttons["New task"].tap()
        let description = app.descendants(matching: .any).matching(identifier: "task-description").firstMatch
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        description.typeText("Task after denied Reminders access")
        XCTAssertEqual(description.value as? String, "Task after denied Reminders access")
        tapTaskControlAtCenter(app.buttons["dismiss-editor-keyboard"], app: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        tapTaskControl(app.buttons["save-task"], app: app)
        XCTAssertTrue(waitForTaskSave(app, row: taskRow(named: "Task after denied Reminders access", app: app), timeout: 10))
    }

    private func openImport(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20))
        openWorkspaceSetting("reminders-import", app: app)
        XCTAssertTrue(app.buttons["reminders-access"].waitForExistence(timeout: 10))
    }

    private func permission(allow: Bool) {
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        let buttons = alert.buttons.allElementsBoundByIndex
        let button = buttons.first { value in
            let label = value.label.lowercased()
            let denied = label.contains("don’t") || label.contains("don't") || label.contains("not allow")
            return label.contains("allow") && (allow ? !denied : denied)
        }
        XCTAssertNotNil(button, "Real system permission choices: \(buttons.map(\.label))")
        button?.tap()
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
