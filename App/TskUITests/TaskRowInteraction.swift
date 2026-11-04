import XCTest

extension XCTestCase {
    @MainActor func assertTodayTaskList(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let title = app.staticTexts["workspace-title-text"]
            return title.exists && title.label == "Today" && app.collectionViews["task-list"].exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed, "Today must show its task list", file: file, line: line)
        XCTAssertFalse(app.staticTexts["Tasks · Today"].exists, file: file, line: line)
    }

    @MainActor func taskTestApplication() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable"
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
    @MainActor func openTaskInformation(_ row: XCUIElement, app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let started = ProcessInfo.processInfo.systemUptime
        let deadline = started + TaskControlReadinessPolicy.accessibilityAdmissionTimeout
        let identity: TaskRowControlIdentity
        do {
            let snapshot = try row.snapshot()
            guard snapshot.elementType == .button, let selected = TaskRowControlIdentity(snapshot.identifier),
                  ProcessInfo.processInfo.systemUptime < deadline else {
                XCTFail("Task information requires an observed row identity within its readiness deadline", file: file, line: line)
                return
            }
            identity = selected
        } catch {
            XCTFail("Task row identity snapshot failed: \(error)", file: file, line: line)
            return
        }
        print("Task row identity admission: \(identity.rawValue); readSeconds=\(ProcessInfo.processInfo.systemUptime - started)")
        tapTaskControl(app.buttons[identity.rawValue], app: app, deadline: deadline, file: file, line: line)
        let informationQuery = app.buttons.matching(identifier: "task-row-information")
        if informationQuery.firstMatch.waitForExistence(timeout: 2) {
            let informationDeadline = ProcessInfo.processInfo.systemUptime + TaskControlReadinessPolicy.accessibilityAdmissionTimeout
            let controls = informationQuery.allElementsBoundByAccessibilityElement
            guard controls.count == 1, let information = controls.first,
                  ProcessInfo.processInfo.systemUptime < informationDeadline else {
                XCTFail("Task information requires one native control within its readiness deadline", file: file, line: line)
                return
            }
            let editor = app.scrollViews["task-row-supporting-scroll"]
            if !information.isHittable { editor.swipeUp() }
            tapTaskControl(information, app: app, deadline: informationDeadline, file: file, line: line)
            XCTAssertTrue(app.collectionViews["task-detail-form"].waitForExistence(timeout: 10))
        }
    }
}

extension XCTestCase {
    @MainActor func openTaskRowParameter(_ identifier: String, app: XCUIApplication) {
        tapTaskRowPill("row-" + identifier, app: app)
    }

    @MainActor func tapTaskRowPill(_ identifier: String, app: XCUIApplication) {
        let parameters = app.scrollViews["row-date-parameters"]
        let button = app.buttons[identifier]
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
        XCTFail("Attribute pill could not be reached: \(identifier); frame=\(button.frame); viewport=\(parameters.frame)")
    }
}

extension XCTestCase {
    @MainActor func closeTaskRow(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = ProcessInfo.processInfo.systemUptime + TaskControlReadinessPolicy.accessibilityAdmissionTimeout
        var previous: TaskRowOutsideGeometry?
        var latest: TaskRowOutsideGeometry?
        var latestAnchor: XCUIElement?
        var lastSample = "not sampled"
        func require(_ condition: Bool, _ reason: String) throws {
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                throw TaskRowOutsideGeometry.Failure(reason: "deadline expired")
            }
            guard condition else { throw TaskRowOutsideGeometry.Failure(reason: reason) }
        }
        func sample() -> Bool {
            do {
                try require(true, "deadline expired")
                try require(app.state == .runningForeground, "application is not foreground")
                let snapshot = try app.snapshot()
                var nodes: [TaskRowOutsideGeometry.Node] = []
                func collect(_ value: any XCUIElementSnapshot, ancestors: [Int], path: [Int]) throws {
                    try require(nodes.count < 4096, "snapshot node cap")
                    let kind: TaskRowOutsideGeometry.ElementType
                    switch value.elementType {
                    case .other: kind = .other
                    case .window: kind = .window
                    case .cell: kind = .cell
                    case .collectionView: kind = .collectionView
                    case .navigationBar: kind = .navigationBar
                    case .tabBar: kind = .tabBar
                    case .toolbar: kind = .toolbar
                    case .keyboard: kind = .keyboard
                    case .button: kind = .button
                    case .switch: kind = .switch
                    case .textField: kind = .textField
                    case .textView: kind = .textView
                    case .searchField: kind = .searchField
                    case .link: kind = .link
                    case .slider: kind = .slider
                    case .stepper: kind = .stepper
                    case .picker: kind = .picker
                    case .pickerWheel: kind = .pickerWheel
                    case .datePicker: kind = .datePicker
                    case .segmentedControl: kind = .segmentedControl
                    case .scrollBar: kind = .scrollBar
                    case .sheet: kind = .sheet
                    case .popover: kind = .popover
                    case .alert: kind = .alert
                    case .dialog: kind = .dialog
                    case .menu: kind = .menu
                    default: kind = .unclassified
                    }
                    let index = nodes.count
                    nodes.append(.init(value: .init(elementType: kind, identifier: value.identifier,
                                                    frame: value.frame, isEnabled: value.isEnabled),
                                       ancestors: ancestors, path: path))
                    for (childIndex, child) in value.children.enumerated() {
                        try collect(child, ancestors: ancestors + [index], path: path + [childIndex])
                    }
                }
                try collect(snapshot, ancestors: [], path: [])
                let current = try TaskRowOutsideGeometry.admit(applicationFrame: snapshot.frame, nodes: nodes)
                let lists = app.collectionViews.matching(identifier: current.listIdentifier)
                    .containing(.any, identifier: "task-description").allElementsBoundByAccessibilityElement
                try require(lists.count == 1, "physical task list is unavailable or ambiguous")
                let anchor: XCUIElement
                if current.reportedAppFrame.isEmpty {
                    let windows = app.windows.containing(.any, identifier: "task-description").allElementsBoundByAccessibilityElement
                    try require(windows.count == 1, "coordinate window is unavailable or ambiguous")
                    anchor = windows[0]
                } else {
                    anchor = app
                }
                try require(true, "deadline expired")
                latest = current
                latestAnchor = anchor
                let stable = previous == current
                previous = current
                lastSample = "\(current.diagnostic) stable=\(stable)"
                return stable
            } catch {
                previous = nil
                latest = nil
                latestAnchor = nil
                lastSample = String(describing: error)
                return false
            }
        }
        var ready = sample()
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        if !ready && remaining > 0 {
            let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in sample() }, object: nil)
            ready = XCTWaiter.wait(for: [expectation], timeout: remaining) == .completed
        }
        guard ready, ProcessInfo.processInfo.systemUptime < deadline, let geometry = latest, let anchor = latestAnchor else {
            let detail = XCTAttachment(string: "Outside gesture admission: \(lastSample)\n" + app.debugDescription)
            detail.name = "Outside gesture admission failure"; detail.lifetime = .keepAlways; add(detail)
            let picture = XCTAttachment(screenshot: app.screenshot())
            picture.name = "Outside gesture admission endpoint"; picture.lifetime = .keepAlways; add(picture)
            XCTFail("No admitted physical outside-save point: \(lastSample)", file: file, line: line)
            return
        }
        print("Outside gesture admitted: \(lastSample)")
        let coordinate = anchor.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: geometry.target.midX - geometry.appFrame.minX,
                                 dy: geometry.target.midY - geometry.appFrame.minY))
        guard ProcessInfo.processInfo.systemUptime < deadline else {
            XCTFail("Outside-save admission expired before native input", file: file, line: line)
            return
        }
        coordinate.tap()
    }
}
