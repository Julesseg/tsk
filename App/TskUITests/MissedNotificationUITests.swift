import XCTest

@MainActor
final class MissedNotificationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testRealEncryptedFinalStateDeliversNewMissedOnceAndCancelsReceivedCompletion() throws {
        let app = taskTestApplication()
        let token = UUID().uuidString
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = "missed-notifications-" + token
        app.launchEnvironment["TSK_TEST_MISSED_NOTIFICATION_FIXTURE"] = token
        for key in ["TSK_UI_ISOLATED_SIMULATOR", "TSK_UI_SYNC_SERVER_URL", "TSK_UI_SYNC_SECRET", "TSK_UI_MISSED_CLIENT_ID"] {
            app.launchEnvironment[key] = try XCTUnwrap(ProcessInfo.processInfo.environment[key], "The canonical real-server fixture must forward " + key)
        }
        app.launch()
        openNotifications(app)
        allowNotifications(app)
        run("missed-fixture-sync", expecting: "SYNCED missed=2 completed=0 deleted=0 local=0", app: app)
        run("missed-fixture-delivered", expecting: "DELIVERED missed=1 suppressed=3", app: app)
        capture("Actual encrypted final snapshot delivers only the newly learned combined missed alert", app)
        app.terminate()
        app.launch()
        openNotifications(app)
        run("missed-fixture-repeat", expecting: "REPEATED accepted=2 no-resubmission", app: app)
        capture("Fresh manager and no-change sync preserve accepted constituents and actual delivery timestamp", app)
        run("missed-fixture-cancel", expecting: "CANCELED remote future after sync", app: app)
        capture("Remote completion cancels the real future request after reaching this device", app)
    }

    private func openNotifications(_ app: XCUIApplication) {
        let entry = app.buttons["notification-settings"].firstMatch
        if app.collectionViews["workspace-sidebar"].exists {
            XCTAssertTrue(revealTaskElement(entry, in: "workspace-sidebar", app: app))
        } else if !entry.waitForExistence(timeout: 5) {
            let more = app.buttons["workspace-more"].firstMatch
            XCTAssertTrue(more.waitForExistence(timeout: 20), app.debugDescription); more.tap()
        }
        XCTAssertTrue(entry.waitForExistence(timeout: 10), app.debugDescription); tapTaskMenuItem(entry, app: app)
        XCTAssertTrue(app.staticTexts["notification-permission"].waitForExistence(timeout: 15))
    }
    private func allowNotifications(_ app: XCUIApplication) {
        let permission = app.buttons["notification-request-permission"]
        if permission.waitForExistence(timeout: 3) {
            permission.tap()
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let allow = springboard.buttons["Allow"].firstMatch
            XCTAssertTrue(allow.waitForExistence(timeout: 10), springboard.debugDescription); allow.tap()
        } else if app.staticTexts["notification-permission"].label == "Notifications disabled in system settings" {
            let link = app.links["Open notification settings"].firstMatch
            XCTAssertTrue(link.waitForExistence(timeout: 5)); link.tap()
            let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
            XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 15))
            let toggle = settings.switches["Allow Notifications"].firstMatch
            if !toggle.waitForExistence(timeout: 5) { settings.cells.containing(.staticText, identifier: "Notifications").firstMatch.tap() }
            XCTAssertTrue(toggle.waitForExistence(timeout: 10), settings.debugDescription)
            if toggle.value as? String == "0" { toggle.tap() }
            app.activate()
            let retry = app.buttons["notification-retry"]
            reveal(retry, in: app); retry.tap()
        }
        XCTAssertTrue(wait(app.staticTexts["notification-permission"], prefix: "Notifications allowed", timeout: 15), app.debugDescription)
    }
    private func run(_ identifier: String, expecting result: String, app: XCUIApplication) {
        let button = app.buttons[identifier]
        reveal(button, in: app); button.tap()
        XCTAssertTrue(wait(app.staticTexts["missed-fixture-result"], prefix: result, timeout: 40), app.debugDescription)
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<16 {
            if element.exists && element.isHittable && app.frame.contains(element.frame) { return }
            if element.exists && element.frame.midY < app.frame.midY { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }
    private func wait(_ element: XCUIElement, prefix: String, timeout: TimeInterval) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in element.exists && element.label.hasPrefix(prefix) }, object: nil)], timeout: timeout) == .completed
    }
    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
