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
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_WIDGET_FIXTURE"] = token
        app.launchEnvironment["TSK_UI_ISOLATED_SIMULATOR"] = "1"
        app.launch()
        XCTAssertTrue(taskRow(named: today, app: app).waitForExistence(timeout: 30))
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCUIDevice.shared.press(.home)
        let home = springboard.otherElements["Home screen icons"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 15), springboard.debugDescription)
        let icon = home.icons["tsk"].firstMatch
        for _ in 0..<3 {
            if icon.exists && icon.isHittable { break }
            home.swipeLeft()
        }
        XCTAssertTrue(icon.waitForExistence(timeout: 15))
        XCTAssertTrue(icon.isHittable)
        capture("Actual Home screen tsk icon before widget installation", springboard)
        icon.press(forDuration: 1.5)
        let editHome = springboard.buttons["Edit Home Screen"].firstMatch
        let options = springboard.buttons["Options"].firstMatch
        if !editHome.exists, options.exists && options.isHittable {
            capture("Actual Home icon native Options menu before editing route", springboard)
            options.tap()
            capture("Actual Home icon Options submenu", springboard)
            let hierarchy = XCTAttachment(string: springboard.debugDescription)
            hierarchy.name = "Actual Home icon Options submenu accessibility"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        }
        let nativeMedium = springboard.buttons["Medium-sized widget"].firstMatch
        if nativeMedium.exists {
            XCTAssertTrue(nativeMedium.isHittable, springboard.debugDescription)
            capture("Actual native app icon medium widget control", springboard)
            nativeMedium.tap()
            if springboard.buttons["Done"].exists && springboard.buttons["Done"].isHittable { springboard.buttons["Done"].tap() }
        } else {
            enterHomeEditing(springboard)
            tap(springboard, labels: ["Edit", "Add Widget", "Add Widgets"])
            if springboard.buttons["Add Widget"].waitForExistence(timeout: 3) { springboard.buttons["Add Widget"].tap() }
            else if springboard.buttons["Add Widgets"].exists { springboard.buttons["Add Widgets"].tap() }
            let search = springboard.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 10))
            search.tap()
            search.typeText("tsk")
            let gallery = springboard.collectionViews["add-sheet-collection-view"].firstMatch
            let provider = gallery.cells.matching(NSPredicate(format: "label IN %@", ["tsk", "tsk Tasks"])).firstMatch
            XCTAssertTrue(provider.waitForExistence(timeout: 15), springboard.debugDescription)
            XCTAssertTrue(provider.isHittable, springboard.debugDescription)
            capture("Actual tsk provider cell in native widget gallery", springboard)
            provider.tap()
            tap(springboard, labels: ["Add Widget", " Add Widget"])
            tap(springboard, labels: ["Done"])
        }
        let taskText = springboard.staticTexts[today].firstMatch
        let rendered = taskText.waitForExistence(timeout: 30)
        if !rendered {
            capture("Actual native widget installation endpoint without Today task", springboard)
            let hierarchy = XCTAttachment(string: springboard.debugDescription)
            hierarchy.name = "Actual widget installation failure accessibility endpoint"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        }
        XCTAssertTrue(rendered, springboard.debugDescription)
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
        let configuredView = springboard.buttons["Today"].firstMatch
        let configuredViewReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in configuredView.exists && configuredView.isEnabled && configuredView.isHittable }, object: nil)
        guard XCTWaiter.wait(for: [configuredViewReady], timeout: 15) == .completed else {
            XCTFail("Native widget View value must be an enabled hittable Today button\n" + springboard.debugDescription)
            return
        }
        configuredView.tap()
        let filterSearch = springboard.searchFields.firstMatch
        if filterSearch.waitForExistence(timeout: 3) { filterSearch.tap(); filterSearch.typeText(view) }
        let savedView = springboard.staticTexts[view].firstMatch
        tapTaskControl(savedView, app: springboard)
        XCTAssertTrue(filterSearch.waitForNonExistence(timeout: 15), "Native widget view picker did not dismiss after selection")
        XCTAssertTrue(springboard.buttons[view].firstMatch.waitForExistence(timeout: 15), "Native widget configuration did not select the saved view")
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
        let completed = app.tabBars.buttons["Done"]
        tapTaskControl(completed, app: app)
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in completed.exists && completed.isSelected }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
    }

    private func enterHomeEditing(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            let edit = app.buttons["Edit"].firstMatch
            let done = app.buttons["Done"].firstMatch
            if edit.exists && done.exists && edit.isHittable && done.isHittable { return }
            let editHome = app.buttons["Edit Home Screen"].firstMatch
            if editHome.exists && editHome.isHittable { editHome.tap(); return }
            let editHomeText = app.staticTexts["Edit Home Screen"].firstMatch
            if editHomeText.exists && editHomeText.isHittable { editHomeText.tap(); return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTFail("Home screen did not expose its editing controls\n" + app.debugDescription, file: file, line: line)
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
