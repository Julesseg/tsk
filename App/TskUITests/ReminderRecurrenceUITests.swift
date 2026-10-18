import UIKit
import XCTest

@MainActor
final class ReminderRecurrenceUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testActualCurrentWeeklyCopyCreatesDurableTemplateAndPreservesCompletedSourceHistory() throws {
        let (app, token) = launchFixture()
        open("reminders-import", app: app)
        prepareAndSelect(token, in: "reminders-import-form", app: app)
        let preview = app.buttons["reminders-preview"]
        XCTAssertTrue(revealTaskElement(preview, in: "reminders-import-form", app: app)); preview.tap()
        XCTAssertTrue(revealTaskElement(app.staticTexts["reminders-preview-count"], in: "reminders-import-form", app: app))
        XCTAssertTrue(app.staticTexts["reminders-preview-count"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.staticTexts["reminders-preview-count"].label, "1 eligible reminder(s)")
        XCTAssertTrue(revealTaskElement(app.staticTexts["reminders-preview-template"], in: "reminders-import-form", app: app))
        capture("Verified current weekly reminder previews as a template, not a flattened task", app)
        XCTAssertTrue(revealTaskElement(app.buttons["reminders-copy"], in: "reminders-import-form", app: app)); app.buttons["reminders-copy"].tap()
        XCTAssertTrue(app.staticTexts["reminders-result"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.staticTexts["reminders-result"].label, "Copied 1; skipped 1; failed 0.")
        evidence("reminders-fixture-report", in: "reminders-import-form", contains: "Copy left current recurring remainder, five completed history records and unsupported source unchanged", app: app)
        XCTAssertTrue(revealTaskElement(app.buttons["reminders-view-templates"], in: "reminders-import-form", app: app)); app.buttons["reminders-view-templates"].tap()
        inspectTemplate(app)
        app.terminate(); app.launch()
        open("recurring-templates", app: app)
        inspectTemplate(app)
        capture("Recurring copy persists at current incomplete anchor with external generation guidance", app)
    }

    func testActualCurrentWeeklyMoveRemovesOnlyVerifiedRemainderAfterDurableTemplateSave() throws {
        let (app, token) = launchFixture()
        open("continuous-reminders-settings", app: app)
        prepareAndSelect(token, in: "continuous-reminders-form", app: app)
        let enable = app.buttons["continuous-reminders-enable"]
        XCTAssertTrue(revealTaskElement(enable, in: "continuous-reminders-form", app: app)); enable.tap()
        XCTAssertTrue(app.staticTexts["continuous-reminders-result"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.staticTexts["continuous-reminders-result"].label, "Saved 1; removed 1; skipped 1; failed 0.")
        let verify = app.buttons["continuous-reminders-verify-fixture"]
        XCTAssertTrue(revealTaskElement(verify, in: "continuous-reminders-form", app: app)); verify.tap()
        evidence("continuous-reminders-fixture-report", in: "continuous-reminders-form", contains: "Current recurring remainder removed; five completed history records and unsupported source unchanged", app: app)
        capture("Actual recurring move preserves completed history and unsupported source rule", app)
        let templates = app.buttons["continuous-reminders-view-templates"]
        XCTAssertTrue(revealTaskElement(templates, in: "continuous-reminders-form", app: app)); templates.tap()
        inspectTemplate(app)
        capture("Durable recurring replacement is reachable directly from the move result", app)
    }

    private func inspectTemplate(_ app: XCUIApplication) {
        let template = app.collectionViews["recurring-template-list"].buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "recurring-template-")).firstMatch
        XCTAssertTrue(template.waitForExistence(timeout: 15))
        XCTAssertNotNil(UUID(uuidString: String(template.identifier.dropFirst("recurring-template-".count))))
        tapTaskControl(template, app: app)
        XCTAssertTrue(app.staticTexts["task-detail-description"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["task-detail-description"].label, "Weekly current anchor")
        XCTAssertTrue(revealTaskElement(app.staticTexts["external-generation-explanation"], in: "task-detail-form", app: app))
        for (key, expected) in [("recur", "1week"), ("due", "1896598800"), ("scheduled", "1896598800"), ("status", "recurring")] {
            let field = app.descendants(matching: .any).matching(identifier: "raw-attribute-" + key).firstMatch
            XCTAssertTrue(revealTaskElement(field, in: "task-detail-form", app: app))
            XCTAssertEqual(field.value as? String, expected)
        }
        XCTAssertFalse(app.buttons["complete-task"].exists)
    }

    private func launchFixture() -> (XCUIApplication, String) {
        XCTAssertEqual(ProcessInfo.processInfo.environment["TSK_UI_ISOLATED_SIMULATOR"], "1")
        if UIDevice.current.userInterfaceIdiom == .pad { XCUIDevice.shared.orientation = .landscapeLeft }
        let token = UUID().uuidString, app = taskTestApplication()
        resetOwnedReminderAuthorization(app, token: token, stage: "recurring-before-launch")
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = token
        app.launchEnvironment["TSK_TEST_NOW"] = "1792144800"
        app.launchEnvironment["TSK_UI_ISOLATED_SIMULATOR"] = "1"
        app.launchEnvironment["TSK_TEST_REMINDERS_RECURRING_FIXTURE"] = token
        addTeardownBlock {
            app.terminate()
            app.launchEnvironment.removeValue(forKey: "TSK_TEST_REMINDERS_RECURRING_FIXTURE")
            app.launchEnvironment["TSK_TEST_REMINDERS_CLEANUP"] = token
            app.launch()
            XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 20))
            app.terminate(); self.resetOwnedReminderAuthorization(app, token: token, stage: "recurring-after-cleanup")
            XCUIDevice.shared.orientation = .portrait
        }
        app.launch()
        return (app, token)
    }

    private func open(_ identifier: String, app: XCUIApplication) {
        XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 20))
        openWorkspaceSetting(identifier, app: app)
    }

    private func prepareAndSelect(_ token: String, in container: String, app: XCUIApplication) {
        let access = app.buttons["reminders-access"]
        XCTAssertTrue(revealTaskElement(access, in: container, app: app)); access.tap()
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        let allow = alert.buttons.allElementsBoundByIndex.first { button in
            let label = button.label.lowercased()
            return label.contains("allow") && !label.contains("don't") && !label.contains("don’t")
        }
        XCTAssertNotNil(allow); allow?.tap()
        let identifier = "reminders-list-tsk fixture \(token) recurrence34"
        let list = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: access)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 30), .completed)
        XCTAssertTrue(revealTaskElement(list, in: container, app: app))
        setDateSwitch(identifier, to: true, app: app, in: container, keyboardDismissIdentifier: "dismiss-reminders-keyboard")
    }

    private func evidence(_ identifier: String, in container: String, contains text: String, app: XCUIApplication) {
        let report = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertTrue(revealTaskElement(report, in: container, app: app))
        let evidence = report.value as? String ?? ""
        XCTAssertTrue(evidence.contains(text), evidence)
        let attachment = XCTAttachment(string: evidence)
        attachment.name = "Actual EventKit recurring import, current anchor and completed-history scope"; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
