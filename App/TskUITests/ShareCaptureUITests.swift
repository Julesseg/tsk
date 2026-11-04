import XCTest

@MainActor final class ShareCaptureUITests: XCTestCase {
    private let taskActivityTitles = ["Add to tsk", "tsk"]
    private var capturedSystemShareFailure = false

    override func setUpWithError() throws { continueAfterFailure = false }

    func testSharingTextAndLinksCreatesPlainTasksWithoutAnEditor() throws {
        let app = taskTestApplication()
        defer { app.terminate() }
        app.launch()
        selectAllTasks(app)
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 15))
        app.terminate()
        let host = XCUIApplication(bundleIdentifier: "com.julesseguin.tsk.sharefixture")
        defer { host.terminate() }
        for mode in ["text", "url", "both"] {
            let token = UUID().uuidString
            let text = "Shared article " + token + "\nFull shared text café e\u{301}"
            let url = "https://example.com/tsk-share?fixture=" + token + "#retained"
            let expected = mode == "text" ? text : mode == "url" ? url : text + "\n\n" + url
            host.launchEnvironment["TSK_SHARE_FIXTURE_TOKEN"] = token
            host.launchEnvironment["TSK_SHARE_FIXTURE_MODE"] = mode
            host.launch()
            openExtension(host)
            let result = host.staticTexts["share-fixture-result"]
            let completed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in result.exists && result.label == "Saved" && host.buttons["share-fixture-present"].isHittable }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 15), .completed)
            XCTAssertFalse(host.buttons["save-shared-task"].exists)
            XCTAssertFalse(host.descendants(matching: .any)["share-task-description"].firstMatch.exists)
            capture("Share automatically saved plain \(mode) without an editor", host)
            host.terminate()
            app.launch()
            selectAllTasks(app)
            let row = taskRow(named: expected, app: app)
            XCTAssertTrue(row.waitForExistence(timeout: 15))
            let identity = row.identifier
            openTaskInformation(row, app: app)
            let description = app.staticTexts["task-detail-description"]
            XCTAssertTrue(revealTaskElement(description, in: "task-detail-form", app: app))
            XCTAssertEqual(description.label, expected)
            XCTAssertFalse(app.buttons["advanced-attributes"].exists)
            capture("Shared \(mode) is the complete plain task description", app)
            app.terminate()
            app.launch()
            selectAllTasks(app)
            XCTAssertTrue(taskRow(named: expected, app: app).waitForExistence(timeout: 15))
            XCTAssertEqual(taskRow(named: expected, app: app).identifier, identity)
            app.terminate()
        }
    }

    private func openExtension(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["share-fixture-present"].waitForExistence(timeout: 10))
        app.buttons["share-fixture-present"].tap()
        let sheet = app.collectionViews["activityCollectionView"]
        guard sheet.waitForExistence(timeout: TaskControlReadinessPolicy.accessibilityAdmissionTimeout) else {
            shareDiscoveryEvidence("System activity sheet missing", app: app)
            XCTFail("The host did not present its system activity sheet")
            return
        }
        capture("Real system activity sheet before installed extension discovery", app)
        let direct = activityEntry(taskActivityTitles, in: sheet)
        if direct.exists && direct.isHittable { tapTaskControl(direct, app: app) }
        else {
            var more = activityEntry(["More"], in: sheet)
            if !more.waitForExistence(timeout: 3) || !more.isHittable {
                let row = sheet.scrollViews.containing(.cell, identifier: "shareCell").firstMatch
                for _ in 0..<3 {
                    guard row.exists else { break }
                    let frame = row.frame.intersection(app.frame)
                    guard frame.width > 60, frame.height > 20 else { break }
                    let origin = app.coordinate(withNormalizedOffset: .zero)
                    origin.withOffset(CGVector(dx: frame.maxX - 20 - app.frame.minX, dy: frame.midY - app.frame.minY))
                        .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: frame.minX + 20 - app.frame.minX, dy: frame.midY - app.frame.minY)))
                    more = activityEntry(["More"], in: sheet)
                    if more.exists && more.isHittable { break }
                }
            }
            guard more.waitForExistence(timeout: 10), more.isHittable else {
                shareDiscoveryEvidence("System activity-row More entry missing", app: app)
                XCTFail("System share-sheet More entry is missing")
                return
            }
            tapTaskControl(more, app: app)
            capture("Real system More apps list before installed extension selection", app)
            let apps = app.otherElements["ShareSheet.EditAppsView"].firstMatch
            let titles = NSPredicate(format: "elementType == %lu AND identifier == %@ AND label IN %@", XCUIElement.ElementType.staticText.rawValue, "activityTitleLabel", taskActivityTitles)
            let matches = apps.tables.cells.containing(titles)
            if !matches.firstMatch.exists, app.buttons["Edit"].exists {
                tapTaskControl(app.buttons["Edit"], app: app)
                capture("Real system Edit apps list before installed extension activation", app)
                let row = matches.firstMatch
                guard row.waitForExistence(timeout: 10) else {
                    shareDiscoveryEvidence("Installed extension absent from real Edit apps list", app: app)
                    XCTFail("Installed tsk share extension was absent from the system Edit apps list")
                    return
                }
                let toggle = row.switches.firstMatch
                if toggle.exists, toggle.value as? String == "0" {
                    tapTaskControl(toggle, app: app)
                    let enabled = expectation(for: NSPredicate(format: "value == %@", "1"), evaluatedWith: toggle)
                    XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
                }
                tapTaskControl(apps.navigationBars.buttons["Done"].firstMatch, app: app)
                capture("Real system apps list after installed extension activation", app)
            }
            guard matches.firstMatch.waitForExistence(timeout: 10), let entry = matches.allElementsBoundByIndex.first(where: { $0.isHittable }) else {
                shareDiscoveryEvidence("Installed extension absent from real More apps list", app: app)
                XCTFail("Installed tsk share extension was not discovered")
                return
            }
            tapTaskControl(entry, app: app)
        }
    }

    private func activityEntry(_ titles: [String], in sheet: XCUIElement) -> XCUIElement {
        let cell = sheet.cells.matching(NSPredicate(format: "identifier == %@ AND label IN %@", "shareCell", titles)).firstMatch
        if cell.exists { return cell }
        let matchingTitle = NSPredicate(format: "label IN %@", titles)
        let button = sheet.buttons.matching(matchingTitle).firstMatch
        return button.exists ? button : sheet.staticTexts.matching(matchingTitle).firstMatch
    }

    private func shareDiscoveryEvidence(_ stage: String, app: XCUIApplication) {
        capture(stage, app)
        let hierarchy = XCTAttachment(string: stage + "\n" + app.debugDescription)
        hierarchy.name = "Actual installed-share discovery hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        #if targetEnvironment(simulator)
        guard !capturedSystemShareFailure,
              ProcessInfo.processInfo.environment["TSK_UI_ISOLATED_SIMULATOR"] == "1",
              let token = app.launchEnvironment["TSK_SHARE_FIXTURE_TOKEN"], UUID(uuidString: token) != nil else { return }
        capturedSystemShareFailure = true
        let captureTime = Date().timeIntervalSince1970
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let screenAttached = png.count <= 4 * 1024 * 1024
        if screenAttached {
            let screen = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            screen.name = "Actual system share failure full screen"
            screen.lifetime = .keepAlways
            add(screen)
        }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let state = springboard.state
        let running = state != .unknown && state != .notRunning
        let description = running ? springboard.debugDescription : ""
        let originalBytes = description.utf8.count
        let prefix = String(decoding: description.utf8.prefix(12 * 1024), as: UTF8.self)
        let metadata: [String: Any] = [
            "stage": String(decoding: stage.utf8.prefix(160), as: UTF8.self),
            "captureTime": captureTime,
            "hostState": app.state.rawValue,
            "springBoardState": state.rawValue,
            "screenPNGBytes": png.count,
            "screenAttached": screenAttached,
            "screenOmission": screenAttached ? "none" : "over-cap",
            "hierarchyState": state == .unknown ? "unknown" : state == .notRunning ? "notRunning" : originalBytes == 0 ? "empty" : originalBytes > 12 * 1024 ? "truncated" : "captured",
            "originalHierarchyUTF8Bytes": originalBytes,
            "retainedHierarchyUTF8Bytes": prefix.utf8.count,
            "hierarchyTruncated": originalBytes > 12 * 1024
        ]
        if let header = try? JSONSerialization.data(withJSONObject: metadata, options: .sortedKeys) {
            var text = header
            text.append(Data("\n".utf8))
            text.append(Data(prefix.utf8))
            if text.count > 16 * 1024 { text = Data("Supplemental share hierarchy omitted: formatted attachment exceeded 16KiB.".utf8) }
            let endpoint = XCTAttachment(data: text, uniformTypeIdentifier: "public.plain-text")
            endpoint.name = "Bounded SpringBoard state at share failure"
            endpoint.lifetime = .keepAlways
            add(endpoint)
        }
        #endif
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
