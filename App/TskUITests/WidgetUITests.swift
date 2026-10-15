import XCTest

@MainActor
final class WidgetUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testInstalledWidgetRendersTodayCompletesAndUsesSavedViewWithTruthfulDeletionError() throws {
        XCTAssertEqual(ProcessInfo.processInfo.environment["TSK_UI_ISOLATED_SIMULATOR"], "1", "Widget system fixtures require the canonical disposable simulator lane")
        let token = UUID().uuidString
        let today = "Widget Today " + token
        let custom = "Widget Custom " + token
        let view = "Widget saved " + token
        let app = XCUIApplication()
        app.launchEnvironment["TSK_TEST_WIDGET_FIXTURE"] = token
        app.launchEnvironment["TSK_UI_ISOLATED_SIMULATOR"] = "1"
        app.launch()
        XCTAssertTrue(taskRow(named: today, app: app).waitForExistence(timeout: 30))
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCUIDevice.shared.press(.home)
        let icon = springboard.icons["tsk"].firstMatch
        for _ in 0..<3 {
            if icon.exists && icon.isHittable { break }
            springboard.swipeLeft()
        }
        XCTAssertTrue(icon.waitForExistence(timeout: 15))
        XCTAssertTrue(icon.isHittable)
        icon.press(forDuration: 1.5)
        tap(springboard, labels: ["Edit Home Screen"])
        tap(springboard, labels: ["Edit", "Add Widget", "Add Widgets"])
        if springboard.buttons["Add Widget"].waitForExistence(timeout: 3) { springboard.buttons["Add Widget"].tap() }
        else if springboard.buttons["Add Widgets"].exists { springboard.buttons["Add Widgets"].tap() }
        let search = springboard.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("tsk")
        tap(springboard, labels: ["tsk", "tsk Tasks"])
        tap(springboard, labels: ["Add Widget"])
        tap(springboard, labels: ["Done"])
        let taskText = springboard.staticTexts[today].firstMatch
        XCTAssertTrue(taskText.waitForExistence(timeout: 30), springboard.debugDescription)
        capture("Installed Today widget reads shared tasks", springboard)
        let complete = springboard.buttons["Complete " + today].firstMatch
        XCTAssertTrue(complete.waitForExistence(timeout: 10))
        complete.tap()
        XCTAssertTrue(taskText.waitForNonExistence(timeout: 30))
        app.activate()
        chooseCompleted(app)
        XCTAssertTrue(taskRow(named: today, app: app).waitForExistence(timeout: 15))
        capture("Actual widget action persisted completion in containing app", app)
        XCUIDevice.shared.press(.home)
        let title = springboard.staticTexts["Today"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        title.press(forDuration: 1.5)
        tap(springboard, labels: ["Edit Widget", "Edit “Task view”"])
        tap(springboard, labels: ["Today", "View"])
        let filterSearch = springboard.searchFields.firstMatch
        if filterSearch.waitForExistence(timeout: 3) { filterSearch.tap(); filterSearch.typeText(view) }
        tap(springboard, labels: [view])
        if springboard.buttons["Done"].exists { springboard.buttons["Done"].tap() }
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(springboard.staticTexts[custom].firstMatch.waitForExistence(timeout: 30), springboard.debugDescription)
        capture("Native widget configuration resolves saved custom view", springboard)
        app.terminate()
        app.launchEnvironment["TSK_TEST_WIDGET_DELETE_VIEW"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 20))
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(springboard.staticTexts["Tasks unavailable"].firstMatch.waitForExistence(timeout: 30), springboard.debugDescription)
        XCTAssertFalse(springboard.staticTexts[custom].exists)
        capture("Deleted configured view reports query error without fallback", springboard)
    }

    private func chooseCompleted(_ app: XCUIApplication) {
        if app.buttons["sidebar-view-completed"].exists { app.buttons["sidebar-view-completed"].tap() }
        else { app.segmentedControls.buttons["Completed"].tap() }
    }

    private func tap(_ app: XCUIApplication, labels: [String], file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            for label in labels {
                let button = app.buttons[label].firstMatch
                if button.exists && button.isHittable { button.tap(); return }
                let text = app.staticTexts[label].firstMatch
                if text.exists && text.isHittable { text.tap(); return }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTFail("Missing native system control: " + labels.joined(separator: ", ") + "\n" + app.debugDescription, file: file, line: line)
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
