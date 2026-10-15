import UIKit
import XCTest

@MainActor
final class ContinuousReminderImportUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testRealContinuousMoveSourceChangesForegroundRescanAndDurableReopen() throws {
        let (app, token) = launchFixture()
        openSettings(app)
        allowAndSelect(app, token)
        enable(app)
        XCTAssertTrue(app.staticTexts["continuous-reminders-result"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.staticTexts["continuous-reminders-result"].label, "Saved 2; removed 2; skipped 1; failed 0.")
        readEvidence(app, contains: "Only two eligible sources removed")
        capture("Real continuous move removes only durably copied sources", app)
        let addCapture = app.buttons["continuous-reminders-add-fixture"]
        XCTAssertTrue(revealTaskElement(addCapture, in: "continuous-reminders-form", app: app))
        addCapture.tap()
        let observed = app.staticTexts["Observed fixture capture"]
        XCTAssertTrue(observed.waitForExistence(timeout: 20))
        XCTAssertEqual(app.staticTexts["continuous-reminders-result"].label, "Saved 1; removed 1; skipped 1; failed 0.")
        capture("Actual EventKit change triggers an automatic scan", app)
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "TSK_TEST_REMINDERS_FIXTURE")
        app.launchEnvironment["TSK_TEST_REMINDERS_ADD_ON_OPEN"] = token
        app.launch()
        XCTAssertTrue(taskRow(named: "Foreground fixture capture", app: app).waitForExistence(timeout: 20))
        XCTAssertTrue(taskRow(named: "Copy fixture H", app: app).exists)
        XCTAssertFalse(taskRow(named: "Exclude completed", app: app).exists)
        XCTAssertFalse(taskRow(named: "Exclude unselected", app: app).exists)
        capture("Foreground opportunity imports a real newly available reminder", app)
        app.launchEnvironment.removeValue(forKey: "TSK_TEST_REMINDERS_ADD_ON_OPEN")
        openSettings(app)
        XCTAssertEqual(app.staticTexts["continuous-reminders-status"].label, "Enabled on this device")
        XCTAssertTrue(revealTaskElement(app.buttons["continuous-reminders-disable"], in: "continuous-reminders-form", app: app))
        app.buttons["continuous-reminders-disable"].tap()
        XCTAssertEqual(app.staticTexts["continuous-reminders-status"].label, "Disabled on this device")
    }

    func testActualSourceEditIntoRecurringRuleIsPreservedAndAutomaticMovePauses() throws {
        let (app, token) = launchFixture(pause: true, changed: true)
        openSettings(app); allowAndSelect(app, token); enable(app)
        let resume = app.buttons["continuous-reminders-resume-fixture"]
        XCTAssertTrue(resume.waitForExistence(timeout: 20))
        app.buttons["continuous-reminders-edit-fixture"].tap()
        XCTAssertTrue(app.staticTexts["continuous-reminders-fixture-changed"].waitForExistence(timeout: 10))
        resume.tap()
        XCTAssertTrue(app.staticTexts["continuous-reminders-paused"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["continuous-reminders-result"].label, "Saved 1; removed 0; skipped 0; failed 1.")
        readEvidence(app, contains: "Changed source and newly recurring rule preserved")
        capture("Source edited after durable save stays intact and stops the attempt", app)
        app.buttons["Done"].tap()
        XCTAssertTrue(taskRow(named: "Copy fixture H", app: app).waitForExistence(timeout: 10))
        XCTAssertFalse(taskRow(named: "Copy fixture none", app: app).exists)
        XCTAssertTrue(app.buttons["continuous-reminders-attention"].exists)
    }

    func testInterruptionAndActualPermissionResetAfterCommitLeaveSourceAndTaskAvailable() throws {
        let (app, token) = launchFixture(pause: true)
        app.launchEnvironment["TSK_TEST_REMINDERS_EXPECT_PRESERVED"] = "1"
        openSettings(app); allowAndSelect(app, token); enable(app)
        XCTAssertTrue(app.buttons["continuous-reminders-resume-fixture"].waitForExistence(timeout: 20))
        app.terminate()
        app.resetAuthorizationStatus(for: .reminders)
        app.launchEnvironment.removeValue(forKey: "TSK_TEST_REMINDERS_FIXTURE")
        app.launchEnvironment.removeValue(forKey: "TSK_TEST_REMINDERS_PAUSE_REMOVAL")
        app.launch()
        XCTAssertTrue(taskRow(named: "Copy fixture H", app: app).waitForExistence(timeout: 20))
        openSettings(app)
        XCTAssertTrue(app.staticTexts["continuous-reminders-paused"].waitForExistence(timeout: 10))
        XCTAssertFalse(taskRow(named: "Copy fixture none", app: app).exists)
        let retry = app.buttons["continuous-reminders-retry"]
        XCTAssertTrue(revealTaskElement(retry, in: "continuous-reminders-form", app: app)); retry.tap()
        XCTAssertTrue(app.staticTexts["continuous-reminders-error"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["continuous-reminders-paused"].exists)
        XCTAssertTrue(revealTaskElement(app.buttons["continuous-reminders-disable"], in: "continuous-reminders-form", app: app))
        app.buttons["continuous-reminders-disable"].tap()
        XCTAssertTrue(revealTaskElement(app.buttons["reminders-access"], in: "continuous-reminders-form", app: app))
        app.buttons["reminders-access"].tap()
        grantPermission()
        readEvidence(app, contains: "Verified four source reminders unchanged")
        capture("Interrupted move and revoked access retain source plus durable task", app)
    }

    private func launchFixture(pause: Bool = false, changed: Bool = false) -> (XCUIApplication, String) {
        XCTAssertEqual(ProcessInfo.processInfo.environment["TSK_UI_ISOLATED_SIMULATOR"], "1")
        if UIDevice.current.userInterfaceIdiom == .pad { XCUIDevice.shared.orientation = .landscapeLeft }
        let token = UUID().uuidString
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .reminders)
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = token
        app.launchEnvironment["TSK_UI_ISOLATED_SIMULATOR"] = "1"
        app.launchEnvironment["TSK_TEST_REMINDERS_FIXTURE"] = token
        app.launchEnvironment["TSK_TEST_REMINDERS_VERIFY_TOKEN"] = token
        if pause { app.launchEnvironment["TSK_TEST_REMINDERS_PAUSE_REMOVAL"] = "1" }
        if changed { app.launchEnvironment["TSK_TEST_REMINDERS_EXPECT_CHANGED"] = "1" }
        addTeardownBlock {
            app.terminate()
            app.launchEnvironment.removeValue(forKey: "TSK_TEST_REMINDERS_FIXTURE")
            app.launchEnvironment.removeValue(forKey: "TSK_TEST_REMINDERS_ADD_ON_OPEN")
            app.launchEnvironment.removeValue(forKey: "TSK_TEST_REMINDERS_PAUSE_REMOVAL")
            app.launchEnvironment["TSK_TEST_REMINDERS_CLEANUP"] = token
            app.launch()
            XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 20))
            app.terminate(); app.resetAuthorizationStatus(for: .reminders)
            XCUIDevice.shared.orientation = .portrait
        }
        app.launch()
        return (app, token)
    }

    private func openSettings(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 20))
        if app.collectionViews["workspace-sidebar"].exists {
            XCTAssertTrue(revealTaskElement(app.buttons["continuous-reminders-settings"], in: "workspace-sidebar", app: app))
        } else { app.buttons["workspace-more"].tap() }
        app.buttons["continuous-reminders-settings"].tap()
        XCTAssertTrue(app.buttons["reminders-access"].waitForExistence(timeout: 10))
    }

    private func allowAndSelect(_ app: XCUIApplication, _ token: String) {
        app.buttons["reminders-access"].tap(); grantPermission()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "continuous-reminders-progress").firstMatch.waitForNonExistence(timeout: 30))
        let identifier = "reminders-list-tsk fixture \(token) selected"
        let list = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertTrue(revealTaskElement(list, in: "continuous-reminders-form", app: app))
        setDateSwitch(identifier, to: true, app: app, in: "continuous-reminders-form", keyboardDismissIdentifier: "dismiss-reminders-keyboard")
    }

    private func enable(_ app: XCUIApplication) {
        XCTAssertTrue(revealTaskElement(app.buttons["continuous-reminders-enable"], in: "continuous-reminders-form", app: app))
        app.buttons["continuous-reminders-enable"].tap()
    }

    private func readEvidence(_ app: XCUIApplication, contains expected: String) {
        let button = app.buttons["continuous-reminders-verify-fixture"]
        XCTAssertTrue(revealTaskElement(button, in: "continuous-reminders-form", app: app)); button.tap()
        let report = app.descendants(matching: .any).matching(identifier: "continuous-reminders-fixture-report").firstMatch
        XCTAssertTrue(revealTaskElement(report, in: "continuous-reminders-form", app: app))
        let evidence = report.value as? String ?? ""
        XCTAssertTrue(evidence.contains(expected), evidence)
        let attachment = XCTAttachment(string: evidence)
        attachment.name = "Real EventKit move/readback evidence"; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func grantPermission() {
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        let button = alert.buttons.allElementsBoundByIndex.first {
            let label = $0.label.lowercased()
            return label.contains("allow") && !label.contains("don’t") && !label.contains("don't")
        }
        XCTAssertNotNil(button); button?.tap()
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
