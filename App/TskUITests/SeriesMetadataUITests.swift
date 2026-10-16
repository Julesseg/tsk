import XCTest

@MainActor
final class SeriesMetadataUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testSeriesMetadataPreviewCancelSaveAndPersistentFutureOccurrences() throws {
        let path = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "TaskwarriorRecurringFixture", withExtension: "json"))
        var records = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [[String: Any]])
        let parentIndex = try XCTUnwrap(records.firstIndex { ($0["attributes"] as? [[String: String]] ?? []).contains { $0["key"] == "mask" } })
        let parentID = try XCTUnwrap(records[parentIndex]["id"] as? String)
        for index in records.indices {
            var attributes = try XCTUnwrap(records[index]["attributes"] as? [[String: String]])
            if index == parentIndex {
                let mask = try XCTUnwrap(attributes.firstIndex { $0["key"] == "mask" })
                attributes[mask]["value"] = "+WW"
            } else if attributes.contains(where: { $0["key"] == "imask" && $0["value"] == "0" }) {
                let status = try XCTUnwrap(attributes.firstIndex { $0["key"] == "status" })
                attributes[status]["value"] = "completed"
                attributes.append(["key": "end", "value": "1792144700"])
            }
            records[index]["attributes"] = attributes
        }
        let futureIDs = records.compactMap { record -> String? in
            let attributes = record["attributes"] as? [[String: String]] ?? []
            return attributes.contains { $0["key"] == "parent" } && attributes.contains { $0["key"] == "status" && $0["value"] == "pending" } ? record["id"] as? String : nil
        }
        let app = XCUIApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_NOW"] = "1792144800"
        app.launchEnvironment["TSK_TEST_RECORDED_RECURRENCE"] = String(decoding: try JSONSerialization.data(withJSONObject: records), as: UTF8.self)
        app.launch()
        openTemplate(parentID, app: app)
        XCTAssertTrue(app.buttons["edit-series-metadata"].waitForExistence(timeout: 10))
        app.buttons["edit-series-metadata"].tap()
        let emptyDescription = app.textFields["series-description"].exists ? app.textFields["series-description"] : app.textViews["series-description"]
        XCTAssertTrue(emptyDescription.waitForExistence(timeout: 10))
        replaceTaskText(emptyDescription, with: "", app: app)
        hideKeyboard(app)
        app.buttons["preview-series-metadata"].tap()
        XCTAssertTrue(app.staticTexts["series-metadata-error"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["series-metadata-error"].label.contains("description"))
        capture("Invalid series metadata remains editable without saving", app)
        changeDescription(app)
        app.buttons["preview-series-metadata"].tap()
        assertPreview(futureIDs, app: app)
        capture("Series preview lists two unfinished occurrences and excludes completed history", app)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["edit-series-metadata"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["task-detail-description"].label, "Generated weekly")
        app.buttons["edit-series-metadata"].tap()
        changeDescription(app)
        let project = app.textFields["task-project"]
        XCTAssertTrue(revealTaskElement(project, in: "series-metadata-form", app: app, bottomInset: app.otherElements["series-keyboard-dismissal"].firstMatch))
        project.tap()
        project.typeText("Series.Work")
        hideKeyboard(app)
        let note = app.descendants(matching: .any)["series-new-annotation"].firstMatch
        guard revealTaskElement(note, in: "series-metadata-form", app: app) else { return }
        guard note.elementType == .textField || note.elementType == .textView else {
            XCTFail("The revealed series annotation must be a native text input: " + note.debugDescription)
            return
        }
        tapTaskControl(note, app: app)
        note.typeText("Series metadata note")
        hideKeyboard(app)
        app.buttons["preview-series-metadata"].tap()
        assertPreview(futureIDs, app: app)
        app.buttons["save-series-metadata"].tap()
        XCTAssertTrue(app.buttons["edit-series-metadata"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["task-detail-description"].label, "Revised series metadata")
        capture("Series metadata saved through the shared atomic path", app)
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "TSK_TEST_RECORDED_RECURRENCE")
        app.launch()
        for id in futureIDs {
            let row = app.buttons["task-" + id]
            XCTAssertTrue(row.waitForExistence(timeout: 15))
            XCTAssertTrue(row.label.contains("Revised series metadata"))
        }
        openTemplate(parentID, app: app)
        XCTAssertEqual(app.staticTexts["task-detail-description"].label, "Revised series metadata")
        let mask = app.descendants(matching: .any)["raw-attribute-mask"].firstMatch
        XCTAssertTrue(revealTaskElement(mask, in: "task-detail-form", app: app))
        XCTAssertEqual(mask.value as? String, "+WW")
        capture("Reopened template retains recurrence mask and metadata", app)
    }

    private func openTemplate(_ id: String, app: XCUIApplication) {
        let templates = app.buttons["recurring-templates"]
        let sidebar = app.collectionViews["workspace-sidebar"].firstMatch
        if sidebar.exists && !templates.isHittable {
            guard revealTaskElement(templates, in: sidebar, app: app) else { return }
        }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in templates.exists && templates.isHittable }, object: nil)
        guard XCTWaiter.wait(for: [ready], timeout: 5) == .completed else {
            XCTFail("Recurring templates control is unavailable: " + app.debugDescription)
            return
        }
        tapTaskControl(templates, app: app)
        let row = app.buttons["recurring-template-" + id]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()
    }

    private func changeDescription(_ app: XCUIApplication) {
        let field = app.textFields["series-description"].exists ? app.textFields["series-description"] : app.textViews["series-description"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        replaceTaskText(field, with: "Revised series metadata", app: app)
        hideKeyboard(app)
    }

    private func assertPreview(_ ids: [String], app: XCUIApplication) {
        XCTAssertTrue(app.buttons["save-series-metadata"].waitForExistence(timeout: 10))
        let count = app.staticTexts["series-preview-count"]
        XCTAssertTrue(revealTaskElement(count, in: "series-metadata-form", app: app))
        XCTAssertEqual(count.label, "2 future unfinished occurrences")
        for id in ids { XCTAssertTrue(revealTaskElement(app.descendants(matching: .any)["series-preview-" + id].firstMatch, in: "series-metadata-form", app: app)) }
    }

    private func hideKeyboard(_ app: XCUIApplication) {
        if app.buttons["dismiss-series-keyboard"].exists { app.buttons["dismiss-series-keyboard"].tap() }
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
