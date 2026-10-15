import XCTest

@MainActor final class ShareCaptureUITests: XCTestCase {
    private let taskActivityTitles = ["Add to tsk", "tsk"]
    private var capturedSystemShareFailure = false

    override func setUpWithError() throws { continueAfterFailure = false }

    func testInstalledExtensionFirstFailureCancelEditableSaveAndDurableAppReadback() throws {
        let token = UUID().uuidString
        let host = XCUIApplication(bundleIdentifier: "com.julesseguin.tsk.sharefixture")
        host.launchEnvironment["TSK_SHARE_FIXTURE_TOKEN"] = token
        defer { host.terminate() }
        let app = XCUIApplication()
        defer { app.terminate() }
        host.launch()
        openExtension(host)
        XCTAssertTrue(host.staticTexts["share-save-error"].waitForExistence(timeout: 15))
        XCTAssertTrue(host.staticTexts["share-save-error"].label.contains("Open tsk"))
        XCTAssertFalse(host.buttons["save-shared-task"].isEnabled)
        capture("Actual extension-first shared storage error preserves source draft", host)
        host.buttons["cancel-shared-task"].tap()
        app.launch()
        XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 15))
        XCTAssertFalse(taskRow(named: "Shared article " + token, app: app).exists)
        app.terminate()
        host.terminate()
        host.launch()
        openExtension(host)
        let description = descriptionField(host)
        replace(description, with: "Cancelled share " + token)
        host.buttons["cancel-shared-task"].tap()
        app.launch()
        XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 15))
        XCTAssertFalse(taskRow(named: "Cancelled share " + token, app: app).exists)
        app.terminate()
        host.terminate()
        host.launch()
        openExtension(host)
        replace(descriptionField(host), with: " ")
        host.buttons["save-shared-task"].tap()
        XCTAssertTrue(host.staticTexts["share-save-error"].waitForExistence(timeout: 10))
        XCTAssertTrue(host.staticTexts["share-save-error"].label.contains("description"))
        XCTAssertTrue(revealTaskElement(host.textViews["share-retained-content"], in: "share-task-form", app: host))
        XCTAssertTrue((host.textViews["share-retained-content"].value as? String)?.contains("https://example.com/tsk-share?fixture=" + token) == true)
        capture("Actual extension keeps full shared content after validation failure", host)
        let title = "Saved share " + token
        XCTAssertTrue(revealTaskElement(descriptionField(host), in: "share-task-form", app: host))
        replace(descriptionField(host), with: title)
        let project = host.textFields["task-project"]
        XCTAssertTrue(revealTaskElement(project, in: "share-task-form", app: host))
        project.tap(); project.typeText("Shared.Reading")
        let tag = host.textFields["task-tag-input"]
        XCTAssertTrue(revealTaskElement(tag, in: "share-task-form", app: host))
        tag.tap(); tag.typeText("reference")
        host.buttons["add-tag"].tap()
        setDateSwitch("planned-day-enabled", to: true, app: host, in: "share-task-form", keyboardDismissIdentifier: "dismiss-share-keyboard")
        XCTAssertTrue(revealTaskElement(host.buttons["plan-tomorrow"], in: "share-task-form", app: host))
        host.buttons["plan-tomorrow"].tap()
        setDateSwitch("deadline-enabled", to: true, app: host, in: "share-task-form", keyboardDismissIdentifier: "dismiss-share-keyboard")
        capture("Native share extension reviews organization and independent planned/deadline dates", host)
        host.buttons["save-shared-task"].tap()
        let dismissed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: host.buttons["save-shared-task"])
        let completion = XCTWaiter.wait(for: [dismissed], timeout: 15)
        if completion != .completed { shareDiscoveryEvidence("Actual extension editor after Save did not dismiss", app: host) }
        XCTAssertEqual(completion, .completed)
        app.launch()
        XCTAssertTrue(taskRow(named: title, app: app).waitForExistence(timeout: 15))
        capture("Extension-created task is visible in the main app after process reopen", app)
        taskRow(named: title, app: app).tap()
        XCTAssertTrue(revealTaskElement(app.staticTexts["Project, Shared.Reading"], in: "task-detail-form", app: app))
        XCTAssertTrue(app.staticTexts["Tags, reference"].exists)
        let note = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Full shared text café e\u{301}")).firstMatch
        XCTAssertTrue(revealTaskElement(note, in: "task-detail-form", app: app))
        XCTAssertTrue(note.label.contains("https://example.com/tsk-share?fixture=" + token))
        for key in ["scheduled", "due"] {
            XCTAssertTrue(revealTaskElement(app.descendants(matching: .any)["raw-attribute-" + key].firstMatch, in: "task-detail-form", app: app))
        }
        capture("Main app retains exact shared annotation, project, tag and separate saved dates", app)
    }

    private func openExtension(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["share-fixture-present"].waitForExistence(timeout: 10))
        app.buttons["share-fixture-present"].tap()
        let sheet = app.collectionViews["activityCollectionView"]
        guard sheet.waitForExistence(timeout: 5) else {
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
        guard app.buttons["cancel-shared-task"].waitForExistence(timeout: 15) else {
            shareDiscoveryEvidence("Selected system activity did not expose the extension editor", app: app)
            XCTFail("Installed tsk share extension editor did not open")
            return
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

    private func descriptionField(_ app: XCUIApplication) -> XCUIElement {
        let field = app.textFields["share-task-description"]
        return field.exists ? field : app.textViews["share-task-description"]
    }
    private func replace(_ field: XCUIElement, with value: String) {
        let host = XCUIApplication(bundleIdentifier: "com.julesseguin.tsk.sharefixture")
        let tutorial = host.buttons["Continue"]
        if tutorial.exists, host.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Speed up your typing")).firstMatch.exists { tutorial.tap() }
        replaceTaskText(field, with: value, app: host)
    }
    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
