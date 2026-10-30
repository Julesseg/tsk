import XCTest

@MainActor
final class TaskScheduledUITests: XCTestCase {
    private let taskID = "A6400000-0000-0000-0000-000000000001"

    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { XCUIApplication().terminate() }

    func testNonMidnightScheduledEditsKeepOtherDatesAndPersist() throws {
        let app = try launch()
        app.tabBars.buttons["Today"].tap()
        let todayRow = app.buttons["task-" + taskID]
        XCTAssertTrue(todayRow.waitForExistence(timeout: 10))
        XCTAssertTrue(todayRow.label.contains("Scheduled"))
        XCTAssertTrue(todayRow.label.contains(time(1792170900)))
        XCTAssertTrue(todayRow.label.contains("Deadline"))
        app.tabBars.buttons["Upcoming"].tap()
        XCTAssertTrue(app.collectionViews["upcoming-list"].waitForExistence(timeout: 10))
        let future = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "upcoming-planned-1792250100-")).firstMatch
        XCTAssertTrue(future.waitForExistence(timeout: 5))
        XCTAssertTrue(future.label.contains("Scheduled"))
        XCTAssertTrue(future.label.contains(time(1792250100)))
        let midnight = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", "upcoming-planned-", "A6400000-0000-0000-0000-000000000002")).firstMatch
        XCTAssertTrue(midnight.exists)
        XCTAssertLessThan(midnight.frame.minY, future.frame.minY)
        selectAllTasks(app)
        let row = app.buttons["task-" + taskID]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.buttons["row-scheduled"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["row-scheduled"].value as? String, formatted(1792170900))
        openTaskRowParameter("scheduled", app: app)
        XCTAssertTrue(app.datePickers["scheduled-picker"].waitForExistence(timeout: 5))
        let picker = app.datePickers["scheduled-picker"]
        let timeControl = picker.buttons.matching(NSPredicate(format: "label CONTAINS ':' OR value CONTAINS ':'")).firstMatch
        XCTAssertTrue(timeControl.exists, "Scheduled must expose its native time control: " + picker.debugDescription)
        picker.buttons["Sunday, October 18"].tap()
        app.buttons["close-row-parameter"].tap()
        XCTAssertEqual(app.buttons["row-scheduled"].value as? String, scheduled(on: 18))
        XCTAssertEqual(app.buttons["row-deadline"].value as? String, formatted(1792177200))
        XCTAssertEqual(app.buttons["row-waiting-date"].value as? String, formatted(1792184400))
        app.buttons["task-row-information"].tap()
        XCTAssertTrue(app.collectionViews["task-detail-form"].waitForExistence(timeout: 10))
        XCTAssertTrue(revealTaskElement(app.descendants(matching: .any)["task-planned-day"].firstMatch, in: "task-detail-form", app: app))
        app.buttons["edit-task"].tap()
        XCTAssertTrue(revealTaskElement(app.datePickers["planned-day-picker"], in: "task-editor-form", app: app))
        let tomorrow = app.buttons["plan-tomorrow"]
        XCTAssertTrue(revealTaskElement(tomorrow, in: "task-editor-form", app: app, initialScrollUp: false))
        tomorrow.tap()
        app.buttons["save-task"].tap()
        XCTAssertTrue(app.buttons["edit-task"].waitForExistence(timeout: 10))
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "TSK_TEST_RECORDED_RECURRENCE")
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20))
        selectAllTasks(app)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.buttons["row-scheduled"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["row-scheduled"].value as? String, scheduled(on: 17))
        XCTAssertEqual(app.buttons["row-deadline"].value as? String, formatted(1792177200))
        XCTAssertEqual(app.buttons["row-waiting-date"].value as? String, formatted(1792184400))
        app.terminate()
    }

    func testMidnightScheduledSurvivesUnrelatedEdits() throws {
        let app = try launch()
        selectAllTasks(app)
        let id = "A6400000-0000-0000-0000-000000000002"
        let expected = formatted(Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1792250100)).timeIntervalSince1970)
        let row = app.buttons["task-" + id]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let title = app.textFields["task-description"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["row-scheduled"].value as? String, expected)
        title.tap()
        title.typeText(" revised")
        app.buttons["dismiss-row-keyboard"].tap()
        closeTaskRow(app)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        openTaskInformation(row, app: app)
        app.buttons["edit-task"].tap()
        let field = app.descendants(matching: .any)["task-description"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(" shared")
        XCTAssertTrue(revealTaskElement(app.datePickers["planned-day-picker"], in: "task-editor-form", app: app))
        app.buttons["save-task"].tap()
        XCTAssertTrue(app.buttons["edit-task"].waitForExistence(timeout: 10))
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "TSK_TEST_RECORDED_RECURRENCE")
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20))
        selectAllTasks(app)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.contains("revised"))
        XCTAssertTrue(row.label.contains("shared"))
        row.tap()
        XCTAssertTrue(app.buttons["row-scheduled"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["row-scheduled"].value as? String, expected)
        app.terminate()
    }

    private func time(_ seconds: TimeInterval) -> String {
        Date(timeIntervalSince1970: seconds).formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "en_US")))
    }

    private func formatted(_ seconds: TimeInterval) -> String {
        Date(timeIntervalSince1970: seconds).formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: "en_US")))
    }

    private func scheduled(on day: Int) -> String {
        var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date(timeIntervalSince1970: 1792170900))
        components.day = day
        return formatted(Calendar.current.date(from: components)!.timeIntervalSince1970)
    }

    private func launch() throws -> XCUIApplication {
        let app = taskTestApplication()
        app.launchArguments += ["-AppleLocale", "en_US", "-AppleLanguages", "(en)"]
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_NOW"] = "1792144800"
        app.launchEnvironment["TSK_TEST_CALENDAR_PRESENTATION"] = "empty"
        let records: [[String: Any]] = [
            ["id": taskID, "attributes": ["description": "Review the release", "status": "pending", "scheduled": "1792170900", "due": "1792177200", "wait": "1792184400"]],
            ["id": "A6400000-0000-0000-0000-000000000002", "attributes": ["description": "Midnight scheduled work", "status": "pending", "scheduled": String(Int(Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1792250100)).timeIntervalSince1970))]],
            ["id": "A6400000-0000-0000-0000-000000000003", "attributes": ["description": "Afternoon scheduled work", "status": "pending", "scheduled": "1792250100", "due": "1792257300"]]
        ].map { record in
            ["id": record["id"]!, "attributes": (record["attributes"] as! [String: String]).map { ["key": $0.key, "value": $0.value] }]
        }
        app.launchEnvironment["TSK_TEST_RECORDED_RECURRENCE"] = String(decoding: try JSONSerialization.data(withJSONObject: records), as: UTF8.self)
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20))
        return app
    }

}
