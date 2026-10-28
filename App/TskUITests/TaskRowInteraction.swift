import XCTest

extension XCTestCase {
    @MainActor func taskTestApplication() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TSK_UI_DISABLE_ANIMATIONS"] = "1"
        app.launchEnvironment["TSK_UI_TEST_SESSION"] = UUID().uuidString
        return app
    }

    @MainActor func resetOwnedReminderAuthorization(_ app: XCUIApplication, token: String, stage: String) {
        guard ProcessInfo.processInfo.environment["TSK_UI_ISOLATED_SIMULATOR"] == "1", UUID(uuidString: token) != nil else {
            XCTFail("Reminders authorization timeline requires the owned isolated fixture")
            return
        }
        let started = Date().timeIntervalSince1970
        app.resetAuthorizationStatus(for: .reminders)
        let evidence: [String: Any] = ["token": token, "stage": stage, "started": started, "returned": Date().timeIntervalSince1970,
                                       "testProcessID": ProcessInfo.processInfo.processIdentifier]
        let data = try? JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(string: data.map { String(decoding: $0, as: UTF8.self) } ?? "Reset timeline encoding failed")
        attachment.name = "Owned Reminders authorization reset timeline \(stage)"; attachment.lifetime = .keepAlways; add(attachment)
    }

    @MainActor func selectDoneTasks(_ app: XCUIApplication) {
        let done = app.tabBars.buttons["Done"]
        if done.exists { tapTaskControl(done, app: app); return }
        if !app.collectionViews["views-list"].exists { openWorkspaceSetting("custom-views", app: app) }
        let add = app.buttons["activate-completed"]
        XCTAssertTrue(revealTaskElement(add, in: "views-list", app: app))
        if !add.isEnabled {
            let remove = app.buttons["deactivate-projects"]
            XCTAssertTrue(revealTaskElement(remove, in: "views-list", app: app))
            tapTaskControl(remove, app: app)
            XCTAssertTrue(revealTaskElement(add, in: "views-list", app: app, initialScrollUp: false))
        }
        tapTaskControl(add, app: app)
        let row = app.buttons["view-completed"]
        XCTAssertTrue(revealTaskElement(row, in: "views-list", app: app))
        tapTaskControl(row, app: app)
        XCTAssertTrue(app.collectionViews["views-list"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(done.isSelected)
    }

    @MainActor func selectAllTasks(_ app: XCUIApplication) {
        let tab = app.tabBars.buttons["All"]
        guard tab.waitForExistence(timeout: 20) else {
            XCTFail("The All tab must be available before reviewing unfinished tasks")
            return
        }
        tapTaskControl(tab, app: app)
    }

    func taskRow(named description: String, app: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(format: "identifier MATCHES %@ AND (label == %@ OR label BEGINSWITH %@)", "task-[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}", description, description + ", ")
        return app.buttons.matching(predicate).firstMatch
    }
}

extension XCTestCase {
    @MainActor func openTaskInformation(_ row: XCUIElement, app: XCUIApplication) {
        tapTaskControl(row, app: app)
        let information = app.buttons["task-row-information"]
        if information.waitForExistence(timeout: 2) {
            let editor = app.scrollViews["task-row-editor"]
            if !information.isHittable { editor.swipeUp() }
            tapTaskControl(information, app: app)
            XCTAssertTrue(app.collectionViews["task-detail-form"].waitForExistence(timeout: 10))
        }
    }
}

extension XCTestCase {
    @MainActor func openTaskRowParameter(_ identifier: String, app: XCUIApplication) {
        let parameters = app.scrollViews["row-date-parameters"]
        let button = app.buttons["row-" + identifier]
        guard button.waitForExistence(timeout: 5) else {
            XCTFail("Attribute pill is missing: \(identifier)")
            return
        }
        for _ in 0..<12 {
            guard button.exists else {
                XCTFail("Attribute pill is missing: \(identifier)")
                return
            }
            let frame = button.frame
            let visible = frame.intersection(parameters.frame).intersection(app.frame)
            if !visible.isNull && !visible.isEmpty && visible.width >= 44 - 0.001 && visible.height >= 44 - 0.001 && button.isEnabled {
                app.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: visible.midX - app.frame.minX, dy: visible.midY - app.frame.minY)).tap()
                return
            }
            let direction: CGFloat = frame.midX < parameters.frame.midX ? 1 : -1
            let distance = min(parameters.frame.width * 0.4, max(44, abs(frame.midX - parameters.frame.midX)))
            let start = parameters.coordinate(withNormalizedOffset: CGVector(dx: 0.5 - direction * 0.2, dy: 0.5))
            let end = start.withOffset(CGVector(dx: direction * distance, dy: 0))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        XCTFail("Attribute pill could not be reached: \(identifier)")
    }
}

extension XCTestCase {
    @MainActor func closeTaskRow(_ app: XCUIApplication) {
        let keyboard = app.keyboards.firstMatch
        let bottom = keyboard.exists && keyboard.frame.height > 0 ? keyboard.frame.minY : app.frame.maxY
        let viewport = CGRect(x: app.frame.minX, y: app.frame.minY, width: app.frame.width, height: max(0, bottom - app.frame.minY))
        let targets = app.buttons.matching(identifier: "task-row-outside").allElementsBoundByIndex
            .map { ($0, $0.frame.intersection(viewport)) }
            .filter { !$0.1.isNull && !$0.1.isEmpty }
        guard let target = targets.max(by: { $0.1.width * $0.1.height < $1.1.width * $1.1.height }) else {
            XCTFail("No visible outside-tap region for the task row")
            return
        }
        tapTaskControlAtCenter(target.0, app: app,
                               requiresVisibleKeyboard: keyboard.exists && keyboard.frame.height > 0)
    }
}
