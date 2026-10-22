import XCTest
import UIKit

extension XCTestCase {
    @MainActor func taskTestApplication() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TSK_UI_DISABLE_ANIMATIONS"] = "1"
        app.launchEnvironment["TSK_UI_TEST_SESSION"] = UUID().uuidString
        return app
    }

    @MainActor func workspaceTab(_ title: String, app: XCUIApplication) -> XCUIElement {
        if UIDevice.current.userInterfaceIdiom != .pad { return app.tabBars.buttons[title] }
        return app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "tab-", title)).firstMatch
    }

    @MainActor func workspaceTabs(in app: XCUIApplication) -> [XCUIElement] {
        if UIDevice.current.userInterfaceIdiom != .pad { return app.tabBars.buttons.allElementsBoundByIndex }
        var seen: Set<String> = []
        return app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "tab-")).allElementsBoundByIndex.filter {
            seen.insert($0.identifier).inserted
        }
    }

    @MainActor func workspaceMenuView(_ title: String, app: XCUIApplication) -> XCUIElement {
        app.collectionViews.containing(.button, identifier: "manage-favorite-views").buttons[title].firstMatch
    }

    @MainActor func openWorkspaceMenuView(_ title: String, app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        guard activateWorkspaceControl(title, app: app, file: file, line: line) else { return }
        let destination = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let heading = app.staticTexts.matching(identifier: "workspace-title-text").firstMatch
            return !app.buttons["manage-favorite-views"].exists && heading.exists && heading.label == title
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [destination], timeout: 10), .completed, app.debugDescription, file: file, line: line)
    }

    @MainActor func openWorkspaceFavorites(app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        guard activateWorkspaceControl("Manage favorites", app: app, file: file, line: line) else { return }
        let favorites = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !app.buttons["manage-favorite-views"].exists && app.collectionViews["views-list"].exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [favorites], timeout: 10), .completed, app.debugDescription, file: file, line: line)
    }

    @MainActor func openWorkspaceViews(app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        guard activateWorkspaceControl("Views", identifier: "workspace-views", app: app, file: file, line: line) else { return }
        XCTAssertTrue(app.buttons["manage-favorite-views"].waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
    }

    @MainActor private func activateWorkspaceControl(_ title: String, identifier: String? = nil, app: XCUIApplication, file: StaticString, line: UInt) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + TaskControlReadinessPolicy.accessibilityAdmissionTimeout
        var previous: TaskNativeMenuOptionGeometry?
        var lastSample = "not sampled"
        func sample() -> Bool {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return false }
            do {
                let application = try app.snapshot()
                var pending: [(any XCUIElementSnapshot, [CGRect], Bool)] = application.children.map { ($0, [], false) }
                var candidates: [TaskNativeMenuOptionGeometry] = []
                while let (snapshot, ancestors, inViewsMenu) = pending.popLast() {
                    let frames = ancestors + [snapshot.frame]
                    let containsViewsMenu = inViewsMenu || snapshot.elementType == .collectionView && taskSnapshot("manage-favorite-views", type: .button, in: snapshot) != nil
                    let matches = identifier.map { snapshot.identifier == $0 } ?? (containsViewsMenu && snapshot.label == title)
                    if matches, snapshot.elementType == .button, snapshot.isEnabled {
                        candidates.append(TaskNativeMenuOptionGeometry(frame: snapshot.frame, ancestorFrames: ancestors))
                    }
                    pending.append(contentsOf: snapshot.children.map { ($0, frames, containsViewsMenu) })
                }
                lastSample = "matchingRows=\(candidates.count) geometry=\(String(describing: candidates.first))"
                guard candidates.count == 1, let current = candidates.first, current.isVisible else { previous = nil; return false }
                let stable = previous == current
                previous = current
                return stable
            } catch {
                lastSample = "snapshotError=\(error)"
                previous = nil
                return false
            }
        }
        var ready = sample()
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        if !ready, remaining > 0 {
            let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in sample() }, object: nil)
            ready = XCTWaiter.wait(for: [settled], timeout: remaining) == .completed
        }
        guard ready, ProcessInfo.processInfo.systemUptime < deadline else {
            XCTFail("Workspace control did not settle: \(title); \(lastSample); \(app.debugDescription)", file: file, line: line)
            return false
        }
        let control = identifier.map { app.buttons[$0] } ?? workspaceMenuView(title, app: app)
        control.tap()
        return true
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
        let done = workspaceTab("Done", app: app)
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
        let tab = workspaceTab("All", app: app)
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
