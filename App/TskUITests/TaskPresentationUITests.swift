import UIKit
import XCTest

@MainActor final class TaskPresentationUITests: XCTestCase {
    private let ordinaryID = "A0000000-0000-0000-0000-000000000001"
    private let title = "Prepare the release with the product team and review every outstanding accessibility finding"

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
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
            openWorkspaceView("Today", app: app)
            let row = app.buttons["task-" + ordinaryID]
            XCTAssertTrue(row.waitForExistence(timeout: 15))
            XCTAssertTrue(row.label.contains(title))
            XCTAssertTrue(row.label.contains("Release"))
            XCTAssertTrue(row.label.contains("Deadline Today"))
            XCTAssertFalse(row.label.contains("Scheduled Today"))
            XCTAssertFalse(app.staticTexts["Tasks · Today"].exists)
            XCTAssertTrue(row.label.contains("Waiting until"))
            for hidden in ["Active", "Generated occurrence"] {
                XCTAssertFalse(row.label.contains(hidden))
            }
            let circle = app.buttons["complete-task-row-" + ordinaryID]
            let list = app.collectionViews["task-list"]
            let leading = app.descendants(matching: .any)["planner-leading-" + ordinaryID].firstMatch
            XCTAssertTrue(leading.exists)
            XCTAssertLessThan(leading.frame.minX, circle.frame.minX)
            capture("Today " + mode, app)
            openTaskInformation(row, app: app)
            app.terminate()
            app.launchEnvironment["TSK_TEST_NOW"] = "1792144800"
            app.launch()
            XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20))
            openWorkspaceView("Projects", app: app)
            let project = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Release")).firstMatch
            XCTAssertTrue(project.waitForExistence(timeout: 10)); project.tap()
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            capture("Project " + mode, app)
            app.terminate()
        }
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
                record(ordinaryID, ["description": title, "status": "pending", "project": "Release", "scheduled": "1792231200", "due": "1792238400", "wait": "1792324800", "start": "1792141200", "opaque": "preserve unrelated data"])
            ]
        }
        app.launchEnvironment["TSK_TEST_RECORDED_RECURRENCE"] = String(decoding: try JSONSerialization.data(withJSONObject: records), as: UTF8.self)
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20))
        return app
    }


    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Task presentation " + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
