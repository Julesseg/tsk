import XCTest

@MainActor final class ShareCaptureUITests: XCTestCase {
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
        XCTAssertFalse(app.staticTexts["Shared article " + token].exists)
        app.terminate()
        host.terminate()
        host.launch()
        openExtension(host)
        let description = descriptionField(host)
        replace(description, with: "Cancelled share " + token)
        host.buttons["cancel-shared-task"].tap()
        app.launch()
        XCTAssertTrue(app.buttons["new-task"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["Cancelled share " + token].exists)
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
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 15), .completed)
        app.launch()
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 15))
        capture("Extension-created task is visible in the main app after process reopen", app)
        app.staticTexts[title].tap()
        XCTAssertTrue(revealTaskElement(app.staticTexts["Shared.Reading"], in: "task-detail-form", app: app))
        XCTAssertTrue(app.staticTexts["reference"].exists)
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
        let entry = app.buttons["Add to tsk"].firstMatch
        if !entry.waitForExistence(timeout: 5) || !entry.isHittable {
            let more = app.buttons["More"].firstMatch
            if !more.waitForExistence(timeout: 3) || !more.isHittable {
                let row = app.collectionViews.firstMatch
                if row.exists { row.swipeLeft() }
            }
            XCTAssertTrue(more.waitForExistence(timeout: 10), "System share-sheet More entry is missing")
            more.tap()
            let name = app.staticTexts["Add to tsk"].firstMatch
            XCTAssertTrue(name.waitForExistence(timeout: 10), "Installed tsk share extension was not discovered")
            name.tap()
        } else { entry.tap() }
        XCTAssertTrue(app.buttons["cancel-shared-task"].waitForExistence(timeout: 15))
    }
    private func descriptionField(_ app: XCUIApplication) -> XCUIElement {
        let field = app.textFields["share-task-description"]
        return field.exists ? field : app.textViews["share-task-description"]
    }
    private func replace(_ field: XCUIElement, with value: String) {
        field.tap()
        let host = XCUIApplication(bundleIdentifier: "com.julesseguin.tsk.sharefixture")
        let tutorial = host.buttons["Continue"]
        if tutorial.exists, host.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Speed up your typing")).firstMatch.exists { tutorial.tap() }
        field.typeKey("a", modifierFlags: .command)
        field.typeText(value)
    }
    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
