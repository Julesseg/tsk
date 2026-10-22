import UIKit
import XCTest

@MainActor final class TaskPresentationUITests: XCTestCase {
    private let ordinaryID = "A0000000-0000-0000-0000-000000000001"
    private let blockerID = "A0000000-0000-0000-0000-000000000002"
    private let secondBlockerID = "A0000000-0000-0000-0000-000000000003"
    private let title = "Prepare the release with the product team and review every outstanding accessibility finding"

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
    }

    override func tearDownWithError() throws {
        XCUIApplication().terminate()
        XCUIDevice.shared.orientation = .portrait
        XCUIDevice.shared.appearance = .light
    }

    func testMatchedPopulatedTaskListsAcrossAppearanceAndAccessibilityText() throws {
        let replica = UUID().uuidString
        for (appearance, largeText) in [("light", false), ("dark", false), ("light", true), ("dark", true)] {
            XCUIDevice.shared.appearance = appearance == "dark" ? .dark : .light
            let app = try launch(largeText: largeText, now: "1792234800", replica: replica)
            let mode = appearance + (largeText ? " accessibility XXXL" : "")
            app.tabBars.buttons["Today"].tap()
            let row = app.buttons["task-" + ordinaryID]
            XCTAssertTrue(row.waitForExistence(timeout: 15))
            XCTAssertTrue(row.label.contains(title))
            XCTAssertTrue(row.label.contains("Release"))
            XCTAssertTrue(row.label.contains("Due Today"))
            XCTAssertFalse(app.staticTexts["Tasks · Today"].exists)
            XCTAssertFalse(app.buttons["notification-attention"].exists)
            for hidden in ["Active", "Waiting", "Blocked by", "Deadline", "Generated occurrence", "Planned work"] {
                XCTAssertFalse(row.label.contains(hidden))
            }
            let circle = app.buttons["complete-task-row-" + ordinaryID]
            let list = app.collectionViews["task-list"]
            XCTAssertLessThanOrEqual(circle.frame.minX - list.frame.minX, 12)
            capture("Today " + mode, app)
            row.tap()
            let reason = app.collectionViews["task-detail-form"].staticTexts["task-blocked-reason-" + ordinaryID]
            XCTAssertTrue(revealTaskElement(reason, in: "task-detail-form", app: app))
            XCTAssertTrue(reason.label.contains("First prerequisite with a long explanation"))
            XCTAssertTrue(reason.label.contains("Second prerequisite with another long explanation"))
            capture("Full blocker reasons " + mode, app)
            app.terminate()
            app.launchEnvironment["TSK_TEST_NOW"] = "1792144800"
            app.launch()
            XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20))
            app.tabBars.buttons["Upcoming"].tap()
            XCTAssertTrue(upcoming("planned", app).firstMatch.waitForExistence(timeout: 10))
            capture("Upcoming " + mode, app)
            app.tabBars.buttons["Projects"].tap()
            let project = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Release")).firstMatch
            XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            capture("Project " + mode, app)
            let custom = app.tabBars.buttons["Release view"]
            if custom.exists { custom.tap() }
            else {
                openWorkspaceSetting("custom-views", app: app)
                app.buttons["new-custom-view"].tap()
                let name = app.textFields["custom-view-name"]
                XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Release view")
                let filter = app.textViews["raw-filter-expression"]
                replaceTaskText(filter, with: "project.is:Release", app: app)
                app.buttons["save-custom-view"].tap()
                activateSavedWorkspaceView(app)
            }
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            capture("Custom " + mode, app)
            app.terminate()
        }
    }

    func testTaskNotificationPreferencesStayAvailableWithoutAlertReview() throws {
        let replica = UUID().uuidString
        for (appearance, largeText) in [("light", false), ("dark", false), ("light", true), ("dark", true)] {
            XCUIDevice.shared.appearance = appearance == "dark" ? .dark : .light
            let app = try launch(largeText: largeText, now: "1792234800", replica: replica)
            XCTAssertFalse(app.buttons["notification-attention"].exists)
            openWorkspaceSetting("notification-settings", app: app)
            XCTAssertTrue(app.staticTexts["notification-permission"].waitForExistence(timeout: 15))
            XCTAssertTrue(revealTaskElement(app.switches["notification-midnight-enabled"], in: "notification-settings-form", app: app))
            let save = app.buttons["notification-save-preferences"]
            XCTAssertTrue(revealTaskElement(save, in: "notification-settings-form", app: app))
            capture("Notification preferences " + appearance + (largeText ? " accessibility XXXL" : ""), app)
            XCTAssertFalse(app.staticTexts["Registration"].exists)
            XCTAssertFalse(app.buttons["notification-retry"].exists)
            app.terminate()
        }
    }

    func testVisibleCompletionRemovesEveryUpcomingAppearanceAndPersists() throws {
        let app = try launch()
        app.tabBars.buttons["Upcoming"].tap()
        let planned = upcoming("planned", app)
        let deadline = upcoming("deadline", app)
        XCTAssertTrue(planned.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(planned.count, 1); XCTAssertEqual(deadline.count, 1)
        XCTAssertEqual(planned.firstMatch.identifier.suffix(36), deadline.firstMatch.identifier.suffix(36))
        let circle = app.buttons.matching(identifier: "complete-task-row-" + ordinaryID).firstMatch
        XCTAssertTrue(circle.waitForExistence(timeout: 5))
        XCTAssertTrue(circle.isHittable)
        let label = planned.firstMatch.label
        XCTAssertTrue(label.contains("Due Tomorrow"))
        XCTAssertTrue(label.contains("Release"))
        for hidden in ["Deadline", "Active", "Waiting", "Blocked by", "First prerequisite", "Planned work", "Planned day"] {
            XCTAssertFalse(label.contains(hidden))
        }
        XCTAssertTrue(app.staticTexts["Planned work"].exists)
        XCTAssertTrue(app.staticTexts["Deadlines"].exists)
        planned.firstMatch.swipeLeft()
        XCTAssertFalse(app.buttons["Complete"].exists)
        XCTAssertTrue(app.buttons["Edit"].exists)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Upcoming"].tap()
        XCTAssertTrue(circle.waitForExistence(timeout: 10))
        capture("Visible completion before action", app)
        circle.tap()
        XCTAssertTrue(planned.firstMatch.waitForNonExistence(timeout: 15))
        XCTAssertFalse(deadline.firstMatch.exists)
        capture("Completion removes both Upcoming appearances", app)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Upcoming"].tap()
        XCTAssertTrue(app.staticTexts["No upcoming plans or deadlines"].waitForExistence(timeout: 10))
        selectDoneTasks(app)
        XCTAssertTrue(app.buttons["task-" + ordinaryID].waitForExistence(timeout: 10))
        XCTAssertFalse(circle.exists)
    }

    func testOccurrenceCircleCompletionAndGenuineFailureKeepSeriesScope() throws {
        for invalid in [true, false] {
            let app = try launch(occurrence: true, invalid: invalid)
            selectAllTasks(app)
            let circle = app.buttons["complete-task-row-317F6B43-21B9-477D-86DE-920100159891"]
            XCTAssertTrue(circle.waitForExistence(timeout: 15))
            XCTAssertTrue(circle.label.contains("Complete occurrence"))
            circle.tap()
            if invalid {
                let error = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "No tasks were changed")).firstMatch
                XCTAssertTrue(error.waitForExistence(timeout: 10))
                XCTAssertTrue(circle.exists)
                capture("Occurrence completion failure retains task and visible feedback", app)
            } else {
                XCTAssertTrue(circle.waitForNonExistence(timeout: 15))
                XCTAssertTrue(app.buttons["complete-task-row-3E107402-A498-41E6-BD70-DA1DBDBBF96F"].exists)
                capture("Occurrence completion preserves sibling", app)
                app.terminate(); app.launch()
                selectAllTasks(app)
                XCTAssertFalse(circle.exists)
                XCTAssertTrue(app.buttons["complete-task-row-3E107402-A498-41E6-BD70-DA1DBDBBF96F"].exists)
            }
            app.terminate()
        }
    }

    private func launch(largeText: Bool = false, occurrence: Bool = false, invalid: Bool = false, now: String = "1792144800", replica: String = UUID().uuidString) throws -> XCUIApplication {
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = replica
        app.launchEnvironment["TSK_TEST_NOW"] = now
        app.launchEnvironment["TSK_UI_ISOLATED_SIMULATOR"] = "1"
        app.launchEnvironment["TSK_TEST_CALENDAR_PRESENTATION"] = "empty"
        let records: [[String: Any]]
        if occurrence {
            let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "TaskwarriorRecurringFixture", withExtension: "json"))
            var loaded = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
            if invalid {
                let index = try XCTUnwrap(loaded.firstIndex { ($0["attributes"] as? [[String: String]] ?? []).contains { $0["key"] == "mask" } })
                var attributes = try XCTUnwrap(loaded[index]["attributes"] as? [[String: String]])
                let mask = try XCTUnwrap(attributes.firstIndex { $0["key"] == "mask" })
                attributes[mask]["value"] = "WW?"; loaded[index]["attributes"] = attributes
            }
            records = loaded
        } else {
            func record(_ id: String, _ attributes: [String: String]) -> [String: Any] {
                ["id": id, "attributes": attributes.map { ["key": $0.key, "value": $0.value] }]
            }
            records = [
                record(ordinaryID, ["description": title, "status": "pending", "project": "Release", "scheduled": "1792231200", "due": "1792238400", "wait": "1792324800", "start": "1792141200", "dep_" + blockerID.lowercased(): "x", "dep_" + secondBlockerID.lowercased(): "x", "depends": blockerID.lowercased() + "," + secondBlockerID.lowercased(), "opaque": "preserve unrelated data"]),
                record(blockerID, ["description": "First prerequisite with a long explanation", "status": "pending", "scheduled": "1792108800"]),
                record(secondBlockerID, ["description": "Second prerequisite with another long explanation", "status": "pending", "scheduled": "1792108800"])
            ]
        }
        app.launchEnvironment["TSK_TEST_RECORDED_RECURRENCE"] = String(decoding: try JSONSerialization.data(withJSONObject: records), as: UTF8.self)
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20))
        return app
    }

    private func upcoming(_ role: String, _ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "upcoming-" + role + "-"))
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Task presentation " + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
