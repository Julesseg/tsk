import XCTest

@MainActor
final class AutomaticSynchronizationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testAutomaticFailureKeepsCaptureAvailableAndRetriesOnRelaunch() throws {
        let app = taskTestApplication()
        let authenticationService = XCUIApplication(bundleIdentifier: "com.apple.AuthenticationServicesUI")
        var dismissedPassword = false
        var observedPassword = false
        var observedPasswordDialog: (element: XCUIElement, queryRoot: String)?
        var passwordAction = "No exact Save Password? prompt observed"
        addTeardownBlock {
            guard (self.testRun?.totalFailureCount ?? 0) > 0 else { return }
            let attachment = XCTAttachment(string: passwordAction)
            attachment.name = "Actual password prompt query root and action"
            attachment.lifetime = .keepAlways
            self.add(attachment)
        }
        func dismissPassword(_ dialog: XCUIElement, queryRoot: String = "target-app", before deadline: TimeInterval? = nil) -> Bool {
            guard deadline.map({ ProcessInfo.processInfo.systemUptime < $0 }) ?? true,
                  !dismissedPassword, dialog.exists,
                  dialog.elementType == .alert || dialog.elementType == .sheet,
                  dialog.label == "Save Password?" else { return false }
            observedPassword = true
            observedPasswordDialog = (dialog, queryRoot)
            passwordAction = "queryRoot=\(queryRoot) title=Save Password? action=notRequested"
            let notNow = dialog.buttons["Not Now"]
            guard notNow.exists, let snapshot = try? notNow.snapshot(),
                  snapshot.isEnabled, notNow.isHittable,
                  let application = try? app.snapshot() else { return false }
            let sample = TaskControlReadinessSample(exists: true, enabled: snapshot.isEnabled, hittable: true,
                                                    elementFrame: snapshot.frame, appFrame: application.frame,
                                                    appWindowFrames: application.children.filter { $0.elementType == .window }.map { $0.frame })
            passwordAction += " button=Not Now frame=\(snapshot.frame)"
            guard sample.failureReason == nil, deadline.map({ ProcessInfo.processInfo.systemUptime < $0 }) ?? true else { return false }
            dismissedPassword = true
            passwordAction += " action=requested"
            notNow.tap()
            passwordAction += " action=returned"
            observedPassword = false
            return true
        }
        addUIInterruptionMonitor(withDescription: "Optional system password storage") { dialog in
            dismissPassword(dialog, queryRoot: "interruption-monitor")
        }
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launch()
        openWorkspaceSetting("synchronization-settings", app: app)
        let server = app.textFields["sync-server-url"]
        XCTAssertTrue(server.waitForExistence(timeout: 5))
        server.tap()
        server.typeText("http://127.0.0.1:1")
        let client = app.textFields["sync-client-id"]
        tapTaskControlAtCenter(client, app: app, requiresVisibleKeyboard: true)
        client.typeText("6F88CFF9-4727-4699-8B5E-EE6D530498E4")
        let secret = app.secureTextFields["sync-encryption-secret"]
        tapTaskControlAtCenter(secret, app: app, requiresVisibleKeyboard: true)
        secret.typeText("isolated-ui-test-secret")
        tapTaskControlAtCenter(app.buttons["dismiss-sync-keyboard"], app: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        tapTaskControlAtCenter(app.buttons["save-sync-connection"], app: app)
        XCTAssertTrue(app.staticTexts["sync-connection-saved"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["sync-error"].waitForExistence(timeout: 20))
        app.navigationBars.buttons["Done"].tap()
        XCTAssertFalse(app.staticTexts["task-sync-error"].exists)
        capture("Automatic synchronization failure with local capture available", app)
        func dismissPasswordBeforeSample(_ deadline: TimeInterval) {
            guard !dismissedPassword, ProcessInfo.processInfo.systemUptime < deadline else { return }
            observedPassword = false
            for dialog in [app.sheets["Save Password?"], app.alerts["Save Password?"]] {
                if dismissPassword(dialog, before: deadline) { return }
            }
            guard ProcessInfo.processInfo.systemUptime < deadline else { return }
            let serviceState = authenticationService.state
            guard serviceState == .runningForeground || serviceState == .runningBackground else { return }
            for dialog in [authenticationService.sheets["Save Password?"], authenticationService.alerts["Save Password?"]] {
                if dismissPassword(dialog, queryRoot: "com.apple.AuthenticationServicesUI", before: deadline) { return }
            }
        }
        func prepareCaptureControl() {
            let deadline = ProcessInfo.processInfo.systemUptime + TaskControlReadinessPolicy.accessibilityAdmissionTimeout
            func sample() -> Bool {
                guard ProcessInfo.processInfo.systemUptime < deadline else { return false }
                dismissPasswordBeforeSample(deadline)
                guard !observedPassword, ProcessInfo.processInfo.systemUptime < deadline else { return false }
                return app.buttons["New task"].isHittable && ProcessInfo.processInfo.systemUptime < deadline
            }
            if sample() { return }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            if remaining > 0 {
                let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in sample() }, object: nil)
                _ = XCTWaiter.wait(for: [ready], timeout: remaining)
            }
        }
        prepareCaptureControl()
        if let observedDialog = observedPasswordDialog {
            let passwordDialog = observedDialog.element
            if !dismissedPassword {
                let notNow = passwordDialog.buttons["Not Now"]
                let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    !passwordDialog.exists || (notNow.exists && notNow.isEnabled && notNow.isHittable)
                }, object: nil)
                guard XCTWaiter.wait(for: [ready], timeout: 5) == .completed else {
                    XCTFail("The observed Save Password? sheet must expose an actionable Not Now button")
                    return
                }
                if passwordDialog.exists { XCTAssertTrue(dismissPassword(passwordDialog, queryRoot: observedDialog.queryRoot)) }
            }
            XCTAssertTrue(passwordDialog.waitForNonExistence(timeout: 5))
        }
        tapTaskControl(app.buttons["New task"], app: app, beforeSample: dismissPasswordBeforeSample)
        let description = app.descendants(matching: .any).matching(identifier: "task-description").firstMatch
        func waitForCaptureDescription() -> Bool {
            let deadline = ProcessInfo.processInfo.systemUptime + TaskControlReadinessPolicy.accessibilityAdmissionTimeout
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
            tapTaskControl(app.buttons["New task"], app: app, deadline: deadline)
            return waitUntil { description.exists }
        }
        XCTAssertTrue(waitForCaptureDescription())
        func prepareCaptureFocus() -> Bool {
            let deadline = ProcessInfo.processInfo.systemUptime + TaskControlReadinessPolicy.accessibilityAdmissionTimeout
            func sample() -> Bool {
                guard ProcessInfo.processInfo.systemUptime < deadline else { return false }
                dismissPasswordBeforeSample(deadline)
                guard !observedPassword, ProcessInfo.processInfo.systemUptime < deadline else { return false }
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
        tapTaskControlAtCenter(app.buttons["dismiss-editor-keyboard"], app: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["save-task"].isHittable)
        app.buttons["save-task"].tap()
        XCTAssertTrue(waitForTaskSave(app, named: "Durable work while automatic sync fails", timeout: 10))
        XCTAssertTrue(taskRow(named: "Durable work while automatic sync fails", app: app).isHittable)
        XCTAssertFalse(app.staticTexts["task-sync-error"].exists)
        XCTAssertFalse(app.buttons["retry-task-sync"].exists)
        capture("Saved locally despite automatic network failure", app)
        openWorkspaceSetting("synchronization-settings", app: app)
        XCTAssertTrue(app.staticTexts["sync-error"].waitForExistence(timeout: 20))
        app.buttons["sync-now"].tap()
        XCTAssertTrue(app.staticTexts["sync-error"].waitForExistence(timeout: 20))
        app.navigationBars["Synchronization"].buttons["Done"].tap()
        app.terminate()
        app.launch()
        selectAllTasks(app)
        let reopened = taskRow(named: "Durable work while automatic sync fails", app: app)
        XCTAssertTrue(reopened.waitForExistence(timeout: 10))
        XCTAssertTrue(reopened.isHittable)
        XCTAssertFalse(app.staticTexts["task-sync-error"].exists)
        openWorkspaceSetting("synchronization-settings", app: app)
        XCTAssertTrue(app.staticTexts["sync-error"].waitForExistence(timeout: 20))
        capture("App opening retries without losing local work", app)
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
