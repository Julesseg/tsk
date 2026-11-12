import UIKit
import XCTest

@MainActor
final class WorkspaceSettingsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        XCUIApplication().terminate()
        XCUIDevice.shared.orientation = .portrait
        XCUIDevice.shared.appearance = .light
    }

    func testSettingsRemainReachableAtLargestTextSize() {
        let app = launch(arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(app.buttons["New task"].isHittable)
        XCTAssertTrue(revealWorkspaceSetting("continuous-reminders-settings", app: app))
        capture("After settings at largest text size")
        XCTAssertTrue(app.buttons["continuous-reminders-settings"].isHittable)
        XCTAssertTrue(revealWorkspaceSetting("custom-views", app: app, initialScrollUp: false))
        tapTaskControl(app.buttons["custom-views"], app: app)
        XCTAssertTrue(app.collectionViews["views-list"].waitForExistence(timeout: 5))
        capture("Views at largest text size")
        tapTaskControl(app.buttons["close-views"], app: app)
        tapTaskControl(app.buttons["workspace-settings"], app: app)
        tapTaskControl(app.buttons["close-workspace-settings"], app: app)
        XCTAssertTrue(app.collectionViews["workspace-settings-list"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["New task"].isHittable)
    }

    func testViewsCapacityReorderingAndFirstTabPersistAcrossLaunch() {
        let app = launch(animationsEnabled: true)
        XCTAssertEqual(app.tabBars.buttons.allElementsBoundByIndex.map(\.label), ["Today", "Upcoming", "Projects", "All", "New task"])
        XCTAssertTrue(app.tabBars.buttons["Today"].isSelected)
        openWorkspaceSetting("custom-views", app: app)
        capture("Views with four default active tabs")
        tapTaskControl(app.buttons["new-custom-view"], app: app)
        let name = app.textFields["custom-view-name"]
        focusTaskText(name, app: app)
        name.typeText("All local tasks")
        tapTaskControlAtCenter(app.buttons["dismiss-filter-keyboard"], app: app)
        XCTAssertEqual(name.value as? String, "All local tasks")
        tapTaskControl(app.buttons["save-custom-view"], app: app)
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "saved-view-")).firstMatch
        XCTAssertTrue(revealTaskElement(saved, in: "views-list", app: app))
        let id = String(saved.identifier.dropFirst("saved-view-".count))
        let add = app.buttons["activate-custom-" + id]
        XCTAssertFalse(add.isEnabled)
        capture("Views inactive custom filter at tab capacity")
        let remove = app.buttons["deactivate-unfinished"]
        XCTAssertTrue(revealTaskElement(remove, in: "views-list", app: app, initialScrollUp: false))
        tapTaskControl(remove, app: app)
        XCTAssertTrue(revealTaskElement(add, in: "views-list", app: app))
        XCTAssertTrue(add.isEnabled)
        tapTaskControl(add, app: app)
        XCTAssertTrue(revealTaskElement(saved, in: "views-list", app: app, initialScrollUp: false))
        let source = app.collectionViews["views-list"].cells.containing(.button, identifier: saved.identifier).firstMatch
        let first = app.collectionViews["views-list"].cells.containing(.button, identifier: "view-today").firstMatch
        let handle = source.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Reorder ")).firstMatch
        XCTAssertTrue(handle.exists)
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1,
                   thenDragTo: first.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.1)),
                   withVelocity: .slow, thenHoldForDuration: 1)
        let reorderDeadline = ProcessInfo.processInfo.systemUptime + 5
        let movedIdentifier = "saved-view-" + id
        var lastOrder = "not sampled"
        func reordered() -> Bool {
            guard ProcessInfo.processInfo.systemUptime < reorderDeadline else { return false }
            do {
                let snapshot = try app.collectionViews["views-list"].snapshot()
                var pending: [(any XCUIElementSnapshot, CGRect?)] = [(snapshot, nil)]
                var rows: [String: [CGRect]] = [:]
                while let (item, inheritedRow) = pending.popLast() {
                    let row = item.elementType == .cell ? item.frame : inheritedRow
                    if item.elementType == .button,
                       item.identifier == movedIdentifier || item.identifier == "view-today",
                       let row, !row.isEmpty {
                        rows[item.identifier, default: []].append(row)
                    }
                    pending.append(contentsOf: item.children.map { ($0, row) })
                }
                lastOrder = String(describing: rows)
                guard ProcessInfo.processInfo.systemUptime < reorderDeadline,
                      rows[movedIdentifier]?.count == 1, rows["view-today"]?.count == 1,
                      let moved = rows[movedIdentifier]?.first, let today = rows["view-today"]?.first else { return false }
                return moved.minY < today.minY
            } catch {
                lastOrder = String(describing: error)
                return false
            }
        }
        var orderAcknowledged = reordered()
        let remaining = reorderDeadline - ProcessInfo.processInfo.systemUptime
        if !orderAcknowledged, remaining > 0 {
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in reordered() }, object: nil)
            orderAcknowledged = XCTWaiter.wait(for: [ready], timeout: remaining) == .completed && ProcessInfo.processInfo.systemUptime < reorderDeadline
        }
        XCTAssertTrue(orderAcknowledged, "Native reorder did not put the saved view before Today within five seconds: \(lastOrder)")
        capture("Views reordered custom tab first")
        tapTaskControl(app.buttons["close-views"], app: app)
        app.terminate()
        app.launch()
        let custom = app.tabBars.buttons["All local tasks"]
        XCTAssertTrue(custom.waitForExistence(timeout: 15))
        XCTAssertTrue(custom.isSelected)
        XCTAssertEqual(app.tabBars.buttons.element(boundBy: 0).label, "All local tasks")
        XCTAssertEqual(app.tabBars.buttons.count, 5)
        XCTAssertFalse(app.tabBars.buttons["Done"].exists)
        capture("First active custom tab after relaunch")
        openWorkspaceSetting("custom-views", app: app)
        for identifier in ["today", "upcoming", "projects"] {
            let button = app.buttons["deactivate-" + identifier]
            XCTAssertTrue(revealTaskElement(button, in: "views-list", app: app, initialScrollUp: false))
            tapTaskControl(button, app: app)
        }
        XCTAssertFalse(app.buttons["deactivate-custom-" + id].isEnabled)
        capture("Views keeps one active tab")
        openSavedViewOptions(app)
        tapTaskMenuItem(app.buttons["Delete"], app: app)
        XCTAssertTrue(saved.waitForNonExistence(timeout: 5))
        tapTaskControl(app.buttons["close-views"], app: app)
        XCTAssertEqual(app.tabBars.buttons.count, 2)
        XCTAssertTrue(app.buttons["New task"].isHittable)
    }

    func testSynchronizationProgressStaysBesideWorkspaceTitle() throws {
        let ready = expectation(description: "Deferred synchronization server is listening")
        let server = try DeferredSynchronizationServer(ready: ready)
        defer { server.stop() }
        wait(for: [ready], timeout: 5)
        let port = try XCTUnwrap(server.port)
        let app = launch()
        func dismissPassword(_ deadline: TimeInterval) {
            for dialog in [app.alerts["Save Password?"], app.sheets["Save Password?"]] {
                guard ProcessInfo.processInfo.systemUptime < deadline else { return }
                if dialog.exists {
                    let notNow = dialog.buttons["Not Now"]
                    guard notNow.exists, notNow.isHittable else { return }
                    tapTaskControl(notNow, app: app, deadline: deadline)
                    return
                }
            }
        }
        openWorkspaceSetting("synchronization-settings", app: app)
        let fields = [
            (app.textFields["sync-server-url"], "http://127.0.0.1:\(port)"),
            (app.textFields["sync-client-id"], UUID().uuidString),
            (app.secureTextFields["sync-encryption-secret"], "isolated-progress-test")
        ]
        for (field, value) in fields {
            focusTaskText(field, app: app)
            field.typeText(value)
        }
        tapTaskControlAtCenter(app.buttons["dismiss-sync-keyboard"], app: app)
        tapTaskControl(app.buttons["save-sync-connection"], app: app)
        XCTAssertTrue(app.staticTexts["sync-connection-saved"].waitForExistence(timeout: 5))
        tapTaskControl(app.navigationBars["Synchronization"].buttons["Done"], app: app)
        for title in ["Today", "Projects"] {
            tapTaskControl(app.tabBars.buttons[title], app: app, beforeSample: dismissPassword)
            let progress = app.navigationBars.activityIndicators["workspace-sync-progress"].firstMatch
            XCTAssertTrue(progress.waitForExistence(timeout: 5))
            XCTAssertEqual(app.navigationBars.activityIndicators.matching(identifier: "workspace-sync-progress").count, 1)
            XCTAssertEqual(app.navigationBars.staticTexts.matching(identifier: "workspace-title-text").count, 1)
            let heading = try app.navigationBars.staticTexts["workspace-title-text"].snapshot()
            let progressFrame = try progress.snapshot().frame
            XCTAssertEqual(heading.label, title)
            XCTAssertGreaterThan(heading.frame.width, 0)
            XCTAssertGreaterThan(heading.frame.height, 0)
            XCTAssertTrue(app.frame.contains(heading.frame))
            XCTAssertGreaterThan(progressFrame.minX, heading.frame.maxX)
            XCTAssertEqual(progressFrame.midY, heading.frame.midY, accuracy: 12)
            XCTAssertFalse(app.staticTexts["task-sync-status"].exists)
            XCTAssertFalse(app.staticTexts["task-sync-error"].exists)
            XCTAssertFalse(app.buttons["retry-task-sync"].exists)
        }
        server.finish()
        XCTAssertTrue(app.activityIndicators["workspace-sync-progress"].waitForNonExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["task-sync-status"].exists)
        XCTAssertFalse(app.staticTexts["task-sync-error"].exists)
        let settingsForm = app.collectionViews["workspace-settings-list"]
        var initialSettingsDeadline: TimeInterval?
        var passwordAttempted = false
        var passwordFailure: String?
        var passwordReceipt = "No exact password interruption handled during final Settings navigation"
        addTeardownBlock {
            let attachment = XCTAttachment(string: passwordReceipt)
            attachment.name = "Final Settings password interruption"
            attachment.lifetime = .keepAlways
            self.add(attachment)
        }
        func rejectPassword(_ reason: String) -> Bool {
            passwordFailure = reason
            passwordReceipt += " rejected=\(reason) time=\(ProcessInfo.processInfo.systemUptime)"
            return false
        }
        func dismissFinalPassword(_ dialog: XCUIElement, origin: String, deadline: TimeInterval) -> Bool {
            guard passwordFailure == nil else { return false }
            guard ProcessInfo.processInfo.systemUptime < deadline else { return rejectPassword("deadline expired") }
            guard dialog.exists else { return false }
            guard ProcessInfo.processInfo.systemUptime < deadline else { return rejectPassword("dialog query exceeded deadline") }
            guard let snapshot = try? dialog.snapshot(),
                  snapshot.elementType == .alert || snapshot.elementType == .sheet,
                  snapshot.label == "Save Password?" else { return false }
            guard ProcessInfo.processInfo.systemUptime < deadline else { return rejectPassword("dialog snapshot exceeded deadline") }
            guard !passwordAttempted else { return rejectPassword("A password prompt is present after the single permitted action") }
            passwordReceipt = "origin=\(origin) role=\(snapshot.elementType.rawValue) title=\(snapshot.label) frame=\(snapshot.frame) observed=\(ProcessInfo.processInfo.systemUptime)"
            let buttons = dialog.buttons.matching(NSPredicate(format: "label == %@", "Not Now"))
            guard buttons.count == 1, ProcessInfo.processInfo.systemUptime < deadline else {
                return rejectPassword("Not Now is not unique within the deadline")
            }
            let notNow = buttons.firstMatch
            guard let button = try? notNow.snapshot(), button.elementType == .button,
                  button.label == "Not Now", button.isEnabled,
                  ProcessInfo.processInfo.systemUptime < deadline, notNow.isHittable,
                  ProcessInfo.processInfo.systemUptime < deadline,
                  let application = try? app.snapshot(), ProcessInfo.processInfo.systemUptime < deadline else {
                return rejectPassword("Not Now is not ready within the deadline")
            }
            let frames = [snapshot.frame, button.frame, application.frame]
            guard frames.allSatisfy({ !$0.isNull && !$0.isInfinite && $0.minX.isFinite && $0.minY.isFinite && $0.maxX.isFinite && $0.maxY.isFinite && $0.width > 0 && $0.height > 0 }),
                  snapshot.frame.contains(button.frame) else { return rejectPassword("invalid password geometry") }
            let sample = TaskControlReadinessSample(exists: true, enabled: button.isEnabled, hittable: true,
                                                    elementFrame: button.frame, appFrame: application.frame,
                                                    appWindowFrames: application.children.filter { $0.elementType == .window }.map { $0.frame })
            guard sample.failureReason == nil, ProcessInfo.processInfo.systemUptime < deadline else {
                return rejectPassword("password control is outside its admitted geometry or deadline")
            }
            passwordAttempted = true
            passwordReceipt += " button=Not Now frame=\(button.frame) action=requested time=\(ProcessInfo.processInfo.systemUptime) deadline=\(deadline)"
            print(passwordReceipt)
            guard ProcessInfo.processInfo.systemUptime < deadline else { return rejectPassword("password action admission exceeded deadline") }
            notNow.tap()
            guard ProcessInfo.processInfo.systemUptime < deadline else { return rejectPassword("Not Now returned after deadline") }
            let gone = dialog.waitForNonExistence(timeout: max(0, deadline - ProcessInfo.processInfo.systemUptime))
            guard gone, ProcessInfo.processInfo.systemUptime < deadline else {
                return rejectPassword("matched password prompt did not disappear within the deadline")
            }
            passwordReceipt += " action=returned matchedPromptAbsent=true time=\(ProcessInfo.processInfo.systemUptime)"
            print(passwordReceipt)
            guard ProcessInfo.processInfo.systemUptime < deadline else { return rejectPassword("password completion receipt exceeded deadline") }
            return true
        }
        func prepareFinalPassword(_ deadline: TimeInterval, origin: String) -> Bool {
            guard passwordFailure == nil else { return false }
            guard ProcessInfo.processInfo.systemUptime < deadline else { return rejectPassword("password preparation has no remaining budget") }
            for dialog in [app.alerts["Save Password?"], app.sheets["Save Password?"]] {
                if dismissFinalPassword(dialog, origin: origin, deadline: deadline) { return true }
                if passwordFailure != nil { return false }
            }
            guard ProcessInfo.processInfo.systemUptime < deadline else { return rejectPassword("password preparation exceeded its budget") }
            return true
        }
        if !settingsForm.exists {
            let settings = app.buttons["workspace-settings"]
            XCTAssertTrue(settings.waitForExistence(timeout: 15))
            let deadline = ProcessInfo.processInfo.systemUptime + TaskControlReadinessPolicy.accessibilityAdmissionTimeout
            initialSettingsDeadline = deadline
            do {
                let monitor = addUIInterruptionMonitor(withDescription: "Optional password storage during final Settings opening") { dialog in
                    dismissFinalPassword(dialog, origin: "interruption-monitor", deadline: deadline)
                }
                defer { removeUIInterruptionMonitor(monitor) }
                tapTaskControl(settings, app: app, deadline: deadline, beforeSample: { deadline in
                    if !prepareFinalPassword(deadline, origin: "target-app-pre-tap") {
                        XCTFail(passwordFailure ?? "Final Settings password preparation failed")
                    }
                })
            }
            guard passwordFailure == nil, ProcessInfo.processInfo.systemUptime < deadline else {
                XCTFail(passwordFailure ?? "Final Settings tap returned after its original admission deadline")
                return
            }
        }
        guard revealTaskElement(app.buttons["synchronization-settings"], in: "workspace-settings-list", app: app, prepareAfterFormAppears: {
            guard let deadline = initialSettingsDeadline else {
                return rejectPassword("Post-form preparation has no original Settings admission budget")
            }
            return prepareFinalPassword(deadline, origin: "target-app-post-form")
        }) else { return }
        let destinationDeadline = ProcessInfo.processInfo.systemUptime + TaskControlReadinessPolicy.accessibilityAdmissionTimeout
        tapTaskControl(app.buttons["synchronization-settings"], app: app, deadline: destinationDeadline, beforeSample: { deadline in
            if !prepareFinalPassword(deadline, origin: "target-app-destination") {
                XCTFail(passwordFailure ?? "Synchronization destination password preparation failed")
            }
        })
        guard passwordFailure == nil, ProcessInfo.processInfo.systemUptime < destinationDeadline else {
            XCTFail(passwordFailure ?? "Synchronization destination returned after its original admission deadline")
            return
        }
        XCTAssertTrue(app.staticTexts["sync-error"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["sync-now"].isEnabled)
    }

    private func launch(arguments: [String] = [], animationsEnabled: Bool = false) -> XCUIApplication {
        let app = taskTestApplication()
        if animationsEnabled { app.launchEnvironment["TSK_UI_DISABLE_ANIMATIONS"] = "0" }
        app.launchArguments += arguments
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["workspace-settings"].waitForExistence(timeout: 5))
        return app
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
