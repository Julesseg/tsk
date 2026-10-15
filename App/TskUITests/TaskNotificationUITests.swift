import XCTest

@MainActor
final class TaskNotificationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testActualClosedAppDeliveryCapacityAndLocalMutationReconciliation() throws {
        let app = application()
        app.launch()
        openNotifications(app)
        allowNotifications(app)
        let midnight = app.buttons["notification-fixture-midnight"]
        reveal(midnight, in: app); midnight.tap()
        XCTAssertTrue(wait(app.staticTexts["notification-fixture-result"], prefix: "MIDNIGHT enabled=true hour=9 minute=0", timeout: 15))
        let toggle = app.switches["notification-midnight-enabled"]
        reveal(toggle, in: app, towardsTop: true); tapNotificationSwitch(toggle, app: app)
        let save = app.buttons["notification-save-preferences"]
        reveal(save, in: app, towardsTop: true); tapTaskControl(save, app: app)
        reveal(midnight, in: app); midnight.tap()
        XCTAssertTrue(wait(app.staticTexts["notification-fixture-result"], prefix: "MIDNIGHT enabled=false", timeout: 15))
        capture("Disabled midnight replacement updates actual registration without changing task dates", app)
        reveal(toggle, in: app, towardsTop: true); tapNotificationSwitch(toggle, app: app)
        reveal(save, in: app, towardsTop: true); tapTaskControl(save, app: app)
        let register = app.buttons["notification-fixture-register"]
        reveal(register, in: app)
        register.tap()
        let status = app.staticTexts["notification-fixture-result"]
        XCTAssertTrue(wait(status, prefix: "REGISTERED ", timeout: 20), app.debugDescription)
        let epoch = try XCTUnwrap(Double(status.label.replacingOccurrences(of: "REGISTERED ", with: "")))
        XCTAssertGreaterThan(epoch - Date().timeIntervalSince1970, 10, "The app must terminate before the actual trigger")
        capture("Actual combined pending registration before termination", app)
        app.terminate()
        let terminatedAt = Date().timeIntervalSince1970
        XCTAssertLessThan(terminatedAt, epoch, "The app was actually terminated before the registered trigger")
        let timing = XCTAttachment(string: "registeredTriggerEpoch=\(epoch)\nterminatedEpoch=\(terminatedAt)")
        timing.name = "Closed-app actual termination timing"; timing.lifetime = .keepAlways; add(timing)
        let remaining = max(0, epoch + 5 - Date().timeIntervalSince1970)
        let elapsed = expectation(description: "Fresh notification trigger passes while app is terminated")
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { elapsed.fulfill() }
        wait(for: [elapsed], timeout: remaining + 5)
        app.launch()
        openNotifications(app)
        let delivered = app.buttons["notification-fixture-delivered"]
        reveal(delivered, in: app); delivered.tap()
        XCTAssertTrue(wait(status, prefix: "DELIVERED 1", timeout: 15), app.debugDescription)
        capture("Delivered readback after closed-app trigger without reseeding", app)
        let capacity = app.buttons["notification-fixture-capacity"]
        reveal(capacity, in: app); capacity.tap()
        XCTAssertTrue(wait(status, prefix: "CAPACITY attempted=100 retained=", timeout: 40), app.debugDescription)
        let retained = try XCTUnwrap(Int(status.label.components(separatedBy: "retained=").last ?? ""))
        XCTAssertGreaterThan(retained, 0)
        XCTAssertLessThanOrEqual(retained, 100)
        capture("Actual iOS capacity readback with per-add evidence", app)
        let mutation = app.buttons["notification-fixture-mutation"]
        reveal(mutation, in: app); mutation.tap()
        XCTAssertTrue(wait(status, prefix: "MUTATION VERIFIED", timeout: 20), app.debugDescription)
        capture("Durable date edit and completion reconcile actual pending alerts", app)
    }

    func testActualPermissionRevocationStillAllowsDurableTaskCreation() throws {
        let app = application()
        app.launch()
        openNotifications(app)
        allowNotifications(app)
        let settingsLink = app.links["notification-fixture-system-settings"].firstMatch
        let settingsButton = app.buttons["notification-fixture-system-settings"].firstMatch
        let link = settingsLink.exists ? settingsLink : settingsButton
        reveal(link, in: app); link.tap()
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 15))
        let toggle = notificationPermissionSwitch(in: settings)
        let selectedToggle = notificationSwitchControl(toggle)
        recordTaskSwitchInteraction(row: toggle, selected: selectedToggle, phase: "before-revocation", app: settings)
        if toggle.value as? String == "1" { tapTaskControl(selectedToggle, app: settings) }
        let revoked = XCTWaiter.wait(for: [expectation(for: NSPredicate(format: "value == %@", "0"), evaluatedWith: toggle)], timeout: 5)
        recordTaskSwitchInteraction(row: toggle, selected: selectedToggle, phase: "after-revocation", app: settings)
        XCTAssertEqual(revoked, .completed)
        app.activate()
        let denied = app.buttons["notification-fixture-denied"]
        reveal(denied, in: app); denied.tap()
        XCTAssertTrue(wait(app.staticTexts["notification-fixture-result"], prefix: "DENIED TASK SAVED", timeout: 20), app.debugDescription)
        capture("Actual revoked permission preserves durable task creation", app)
        reveal(link, in: app); link.tap()
        XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 15))
        let restoredToggle = notificationPermissionSwitch(in: settings)
        let selectedRestoredToggle = notificationSwitchControl(restoredToggle)
        recordTaskSwitchInteraction(row: restoredToggle, selected: selectedRestoredToggle, phase: "before-restoration", app: settings)
        if restoredToggle.value as? String == "0" { tapTaskControl(selectedRestoredToggle, app: settings) }
        let restored = XCTWaiter.wait(for: [expectation(for: NSPredicate(format: "value == %@", "1"), evaluatedWith: restoredToggle)], timeout: 5)
        recordTaskSwitchInteraction(row: restoredToggle, selected: selectedRestoredToggle, phase: "after-restoration", app: settings)
        XCTAssertEqual(restored, .completed)
        app.activate()
    }

    private func notificationPermissionSwitch(in settings: XCUIApplication) -> XCUIElement {
        let toggle = settings.switches["Allow Notifications"].firstMatch
        if toggle.waitForExistence(timeout: 5) { return toggle }
        capture("Actual public notification Settings link destination", settings)
        var notifications = settings.cells.containing(.staticText, identifier: "Notifications").firstMatch
        if !notifications.exists {
            let apps = settings.buttons["com.apple.settings.apps"].firstMatch
            let sidebar = settings.collectionViews.matching(NSPredicate(format: "label == %@", "Sidebar")).firstMatch
            let root = sidebar.exists ? sidebar : settings.collectionViews.firstMatch
            guard revealTaskElement(apps, in: root, app: settings, maximumSteps: 12) else { return toggle }
            tapTaskControl(apps, app: settings)
            capture("Actual system Apps settings before selecting tsk", settings)
            let taskApp = settings.cells.containing(.staticText, identifier: "tsk").firstMatch
            let collection = settings.collectionViews.matching(NSPredicate(format: "label != %@", "Sidebar")).firstMatch
            let list = collection.waitForExistence(timeout: 5) ? collection : settings.tables.firstMatch
            if let search = settings.searchFields.allElementsBoundByIndex.first(where: { $0.isHittable && list.frame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }) {
                tapTaskControl(search, app: settings)
                search.typeText("tsk")
            }
            guard revealTaskElement(taskApp, in: list, app: settings, maximumSteps: 12) else { return toggle }
            tapTaskControl(taskApp, app: settings)
            capture("Actual tsk app settings before notification permissions", settings)
            notifications = settings.cells.containing(.staticText, identifier: "Notifications").firstMatch
        }
        XCTAssertTrue(notifications.waitForExistence(timeout: 5), settings.debugDescription)
        tapTaskControl(notifications, app: settings)
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), settings.debugDescription)
        return toggle
    }

    private func application() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TSK_TEST_NOTIFICATION_FIXTURE"] = UUID().uuidString
        app.launchEnvironment["TSK_UI_ISOLATED_SIMULATOR"] = ProcessInfo.processInfo.environment["TSK_UI_ISOLATED_SIMULATOR"] ?? "0"
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = "notifications-" + UUID().uuidString
        return app
    }
    private func openNotifications(_ app: XCUIApplication) {
        let entry = app.buttons["notification-settings"].firstMatch
        if !entry.waitForExistence(timeout: 5) {
            let more = app.buttons["workspace-more"].firstMatch
            XCTAssertTrue(more.waitForExistence(timeout: 20), app.debugDescription)
            more.tap()
        }
        XCTAssertTrue(entry.waitForExistence(timeout: 10), app.debugDescription)
        entry.tap()
        XCTAssertTrue(app.staticTexts["notification-permission"].waitForExistence(timeout: 15))
    }
    private func allowNotifications(_ app: XCUIApplication) {
        let permission = app.buttons["notification-request-permission"]
        if permission.waitForExistence(timeout: 3) {
            permission.tap()
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let allow = springboard.buttons["Allow"].firstMatch
            XCTAssertTrue(allow.waitForExistence(timeout: 10), springboard.debugDescription)
            allow.tap()
        }
        XCTAssertTrue(wait(app.staticTexts["notification-permission"], prefix: "Notifications allowed", timeout: 15), app.debugDescription)
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, towardsTop: Bool = false) {
        revealTaskElement(element, in: "notification-settings-form", app: app, initialScrollUp: !towardsTop, maximumSteps: 12)
    }
    private func tapNotificationSwitch(_ element: XCUIElement, app: XCUIApplication) {
        tapTaskControl(notificationSwitchControl(element), app: app)
    }
    private func notificationSwitchControl(_ element: XCUIElement) -> XCUIElement {
        let thumb = element.switches.firstMatch
        return thumb.exists ? thumb : element
    }
    private func wait(_ element: XCUIElement, prefix: String, timeout: TimeInterval) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in element.exists && element.label.hasPrefix(prefix) }, object: nil)], timeout: timeout) == .completed
    }
    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
