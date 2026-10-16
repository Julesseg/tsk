import XCTest

@MainActor
final class AutomaticSynchronizationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testAutomaticFailureKeepsCaptureAvailableAndRetriesOnRelaunch() throws {
        let app = XCUIApplication()
        var dismissedPassword = false
        func dismissPassword(_ dialog: XCUIElement, before deadline: TimeInterval? = nil) -> Bool {
            guard !dismissedPassword, dialog.exists,
                  dialog.elementType == .alert || dialog.elementType == .sheet,
                  dialog.label == "Save Password?" else { return false }
            let notNow = dialog.buttons["Not Now"]
            guard notNow.exists, let snapshot = try? notNow.snapshot(),
                  snapshot.isEnabled, notNow.isHittable,
                  let application = try? app.snapshot() else { return false }
            let sample = TaskControlReadinessSample(exists: true, enabled: snapshot.isEnabled, hittable: true,
                                                    elementFrame: snapshot.frame, appFrame: application.frame,
                                                    appWindowFrames: application.children.filter { $0.elementType == .window }.map { $0.frame })
            guard sample.failureReason == nil, deadline.map({ ProcessInfo.processInfo.systemUptime < $0 }) ?? true else { return false }
            dismissedPassword = true
            notNow.tap()
            return true
        }
        addUIInterruptionMonitor(withDescription: "Optional system password storage") { dialog in
            dismissPassword(dialog)
        }
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["synchronization-settings"].waitForExistence(timeout: 10))
        app.buttons["synchronization-settings"].tap()
        let server = app.textFields["sync-server-url"]
        XCTAssertTrue(server.waitForExistence(timeout: 5))
        server.tap()
        server.typeText("http://127.0.0.1:1")
        let client = app.textFields["sync-client-id"]
        client.tap()
        client.typeText("6F88CFF9-4727-4699-8B5E-EE6D530498E4")
        let secret = app.secureTextFields["sync-encryption-secret"]
        secret.tap()
        secret.typeText("isolated-ui-test-secret")
        app.buttons["save-sync-connection"].tap()
        XCTAssertTrue(app.staticTexts["sync-error"].waitForExistence(timeout: 20))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["task-sync-error"].waitForExistence(timeout: 10))
        capture("Automatic synchronization failure with local capture available", app)
        let passwordSheet = app.sheets["Save Password?"]
        if passwordSheet.waitForExistence(timeout: 5) {
            let notNow = passwordSheet.buttons["Not Now"]
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                !passwordSheet.exists || (notNow.exists && notNow.isEnabled && notNow.isHittable)
            }, object: nil)
            guard XCTWaiter.wait(for: [ready], timeout: 5) == .completed else {
                XCTFail("The observed Save Password? sheet must expose an actionable Not Now button")
                return
            }
            if passwordSheet.exists { XCTAssertTrue(dismissPassword(passwordSheet)) }
            XCTAssertTrue(passwordSheet.waitForNonExistence(timeout: 5))
        }
        func dismissPasswordBeforeSample(_ deadline: TimeInterval) {
            guard !dismissedPassword else { return }
            for dialog in [app.sheets["Save Password?"], app.alerts["Save Password?"]] {
                if dismissPassword(dialog, before: deadline) { break }
            }
        }
        tapTaskControl(app.buttons["new-task"], app: app, beforeSample: dismissPasswordBeforeSample)
        let description = app.descendants(matching: .any).matching(identifier: "task-description").firstMatch
        func waitForCaptureDescription() -> Bool {
            let deadline = ProcessInfo.processInfo.systemUptime + 5
            func waitUntil(_ sample: @escaping () -> Bool) -> Bool {
                guard ProcessInfo.processInfo.systemUptime < deadline else { return false }
                if sample() { return ProcessInfo.processInfo.systemUptime < deadline }
                let remaining = deadline - ProcessInfo.processInfo.systemUptime
                guard remaining > 0 else { return false }
                let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    ProcessInfo.processInfo.systemUptime < deadline && sample() && ProcessInfo.processInfo.systemUptime < deadline
                }, object: nil)
                return XCTWaiter.wait(for: [ready], timeout: remaining) == .completed && ProcessInfo.processInfo.systemUptime < deadline
            }
            var interrupted = false
            guard waitUntil({
                if description.exists { return true }
                let previouslyDismissed = dismissedPassword
                dismissPasswordBeforeSample(deadline)
                guard ProcessInfo.processInfo.systemUptime < deadline else { return false }
                interrupted = !previouslyDismissed && dismissedPassword
                return interrupted
            }) else { return false }
            if description.exists { return ProcessInfo.processInfo.systemUptime < deadline }
            guard interrupted, ProcessInfo.processInfo.systemUptime < deadline else { return false }
            tapTaskControl(app.buttons["new-task"], app: app, deadline: deadline)
            return waitUntil { description.exists }
        }
        XCTAssertTrue(waitForCaptureDescription())
        func prepareCaptureFocus() -> Bool {
            let deadline = ProcessInfo.processInfo.systemUptime + 5
            func sample() -> Bool {
                guard ProcessInfo.processInfo.systemUptime < deadline else { return false }
                dismissPasswordBeforeSample(deadline)
                guard ProcessInfo.processInfo.systemUptime < deadline else { return false }
                for dialog in [app.sheets["Save Password?"], app.alerts["Save Password?"]] {
                    guard !dialog.exists, ProcessInfo.processInfo.systemUptime < deadline else { return false }
                }
                return app.keyboards.firstMatch.exists && ProcessInfo.processInfo.systemUptime < deadline
            }
            if sample() { return true }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { return false }
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in sample() }, object: nil)
            return XCTWaiter.wait(for: [ready], timeout: remaining) == .completed && ProcessInfo.processInfo.systemUptime < deadline
        }
        XCTAssertTrue(prepareCaptureFocus())
        focusTaskText(description, app: app, beforeSample: dismissPasswordBeforeSample)
        description.typeText("Durable work while automatic sync fails")
        XCTAssertEqual(description.value as? String, "Durable work while automatic sync fails")
        XCTAssertTrue(app.buttons["dismiss-editor-keyboard"].waitForExistence(timeout: 5))
        app.buttons["dismiss-editor-keyboard"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["save-task"].isHittable)
        app.buttons["save-task"].tap()
        XCTAssertTrue(waitForTaskSave(app, row: taskRow(named: "Durable work while automatic sync fails", app: app), timeout: 10))
        XCTAssertTrue(app.staticTexts["Durable work while automatic sync fails"].exists)
        XCTAssertTrue(app.staticTexts["task-sync-error"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["retry-task-sync"].exists)
        capture("Saved locally despite automatic network failure", app)
        app.buttons["retry-task-sync"].tap()
        XCTAssertTrue(app.staticTexts["task-sync-error"].waitForExistence(timeout: 20))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Durable work while automatic sync fails"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["task-sync-error"].waitForExistence(timeout: 20))
        capture("App opening retries without losing local work", app)
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
