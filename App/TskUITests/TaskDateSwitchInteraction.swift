import XCTest

extension XCTestCase {
    func waitForTaskSave(_ app: XCUIApplication, row: XCUIElement, timeout: TimeInterval, editorID: String = "task-editor-form", file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let editor = app.collectionViews[editorID]
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !editor.exists && row.exists }, object: nil)
        guard XCTWaiter.wait(for: [finished], timeout: timeout) == .completed else {
            recordTaskInteraction(app, detail: "Task save did not dismiss its editor and reveal the saved row")
            XCTFail("Task save is not complete; the workspace may still be covered", file: file, line: line)
            return false
        }
        return true
    }

    func waitForEnabledTaskControl(_ element: XCUIElement, app: XCUIApplication, timeout: TimeInterval, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in element.exists && element.isEnabled }, object: nil)
        guard XCTWaiter.wait(for: [ready], timeout: timeout) == .completed else {
            recordTaskInteraction(app, detail: "Control did not become enabled: \(element)")
            XCTFail("The previous task action has not completed", file: file, line: line)
            return false
        }
        return true
    }

    func setDateSwitch(_ identifier: String, to enabled: Bool, app: XCUIApplication, in containerID: String = "task-editor-form", keyboardDismissIdentifier: String = "dismiss-editor-keyboard", file: StaticString = #filePath, line: UInt = #line) {
        let tutorial = app.buttons["Continue"]
        if tutorial.exists, app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Speed up your typing")).firstMatch.exists { tutorial.tap() }
        let keyboardDone = app.buttons[keyboardDismissIdentifier]
        if app.keyboards.firstMatch.exists {
            XCTAssertTrue(keyboardDone.waitForExistence(timeout: 5), file: file, line: line)
            tapTaskControl(keyboardDone, app: app, file: file, line: line)
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "Keyboard still covers task dates", file: file, line: line)
        }
        let control = app.switches[identifier].firstMatch
        guard revealTaskElement(control, in: containerID, app: app, file: file, line: line) else { return }
        let expected = enabled ? "1" : "0"
        if control.value as? String != expected {
            let thumb = control.switches.firstMatch
            let selected = thumb.exists ? thumb : control
            recordTaskSwitchInteraction(row: control, selected: selected, phase: "before", app: app)
            tapTaskControl(selected, app: app, file: file, line: line)
        }
        let changed = expectation(for: NSPredicate(format: "value == %@", expected), evaluatedWith: control)
        let result = XCTWaiter.wait(for: [changed], timeout: 5)
        recordTaskSwitchInteraction(row: control, selected: control.switches.firstMatch.exists ? control.switches.firstMatch : control, phase: "after", app: app)
        XCTAssertEqual(result, .completed, "Date switch did not become \(enabled ? "enabled" : "disabled"): \(identifier)", file: file, line: line)
    }

    func recordTaskSwitchInteraction(row: XCUIElement, selected: XCUIElement, phase: String, app: XCUIApplication) {
        guard ProcessInfo.processInfo.environment["TSK_UI_ISOLATED_SIMULATOR"] == "1" else { return }
        let frame = selected.frame
        let metadata = "phase=\(phase)\nrowIdentifier=\(row.identifier)\nrowValue=\(String(describing: row.value))\nselectedIdentifier=\(selected.identifier)\nselectedValue=\(String(describing: selected.value))\nenabled=\(selected.isEnabled)\nhittable=\(selected.isHittable)\nframe=\(frame)\nappFrame=\(app.frame)\nrequestedTap=\(frame.midX),\(frame.midY)\nrowHierarchy=\(row.debugDescription)"
        let attachment = XCTAttachment(string: metadata)
        attachment.name = "Actual selected switch \(phase) metadata and hierarchy"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func tapTaskControl(_ element: XCUIElement, app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        guard element.waitForExistence(timeout: 5), element.isEnabled, element.isHittable,
              element.frame.width > 0, element.frame.height > 0, app.frame.contains(element.frame) else {
            recordTaskInteraction(app, detail: "Cannot activate \(element)")
            XCTFail("Control has no valid visible hit area: \(element)", file: file, line: line)
            return
        }
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: element.frame.midX - app.frame.minX, dy: element.frame.midY - app.frame.minY)).tap()
    }

    func focusTaskText(_ element: XCUIElement, app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), file: file, line: line)
        if element.isHittable { tapTaskControl(element, app: app, file: file, line: line) }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Text input has no keyboard: \(element)", file: file, line: line)
    }

    func replaceTaskText(_ element: XCUIElement, with value: String, app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        focusTaskText(element, app: app, file: file, line: line)
        element.press(forDuration: 1.1)
        let menu = app.menuItems["Select All"]
        let button = app.buttons["Select All"]
        if menu.exists { menu.tap() }
        else if button.exists { button.tap() }
        else { element.typeKey("a", modifierFlags: .command) }
        element.typeText(XCUIKeyboardKey.delete.rawValue)
        let cleared = element.value as? String ?? ""
        guard cleared.isEmpty || cleared == element.placeholderValue else {
            recordTaskInteraction(app, detail: "Replacement did not clear \(element)")
            XCTFail("Text replacement did not clear the previous value: \(cleared)", file: file, line: line)
            return
        }
        if !value.isEmpty { element.typeText(value) }
        XCTAssertTrue((element.value as? String ?? "") == value || value.isEmpty && (element.value as? String) == element.placeholderValue, "Text replacement value differs", file: file, line: line)
    }

    @discardableResult
    func revealTaskElement(_ element: XCUIElement, in containerID: String, app: XCUIApplication, initialScrollUp: Bool = true, maximumSteps: Int = 14, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        revealTaskElement(element, in: app.collectionViews[containerID].firstMatch, app: app, initialScrollUp: initialScrollUp, maximumSteps: maximumSteps, context: containerID, file: file, line: line)
    }

    @discardableResult
    func revealTaskElement(_ element: XCUIElement, in form: XCUIElement, app: XCUIApplication, initialScrollUp: Bool = true, maximumSteps: Int = 14, context: String = "native settings list", file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard form.waitForExistence(timeout: 5) else {
            recordTaskInteraction(app, detail: "Missing form \(context)")
            XCTFail("Missing task form: \(context)", file: file, line: line)
            return false
        }
        var scrollUp = initialScrollUp
        var missingSteps = 0
        for step in 0...maximumSteps {
            let visible = form.frame.intersection(app.frame)
            let navigationBottom = app.navigationBars.allElementsBoundByIndex.filter {
                $0.exists && $0.isHittable && $0.frame.intersection(visible).width > visible.width / 2 && $0.frame.maxY <= visible.minY + 140
            }.map { $0.frame.maxY }.max() ?? visible.minY
            let pinnedIDs = ["continuous-reminders-status", "continuous-reminders-paused", "continuous-reminders-result", "continuous-reminders-error", "continuous-reminders-stop", "continuous-reminders-resume-fixture", "continuous-reminders-edit-fixture", "continuous-reminders-fixture-changed", "task-editor-error", "series-metadata-error", "transition-error", "annotation-editor-error", "advanced-attributes-error", "filter-error"]
            let pinnedBottom = app.descendants(matching: .any).matching(NSPredicate(format: "identifier IN %@", pinnedIDs)).allElementsBoundByIndex.compactMap { item -> CGFloat? in
                return item.exists && item.isHittable && item.frame.intersects(visible) ? item.frame.maxY : nil
            }.max() ?? visible.minY
            let top = max(visible.minY, navigationBottom, pinnedBottom) + 8
            let keyboard = app.keyboards.firstMatch
            let bottom = min(visible.maxY - 16, keyboard.exists && keyboard.frame.intersects(visible) ? keyboard.frame.minY - 8 : visible.maxY - 16)
            guard visible.width > 0, bottom - top > 60 else { break }
            if element.exists {
                let thumb = element.elementType == .switch ? element.switches.firstMatch : element
                let target = thumb.exists ? thumb : element
                let frame = target.frame
                if frame.minY.isFinite, frame.maxY.isFinite, frame.width > 0, frame.height > 0 {
                    if frame.midY >= top, frame.midY <= bottom, target.isHittable { return true }
                    scrollUp = frame.midY > bottom
                }
            } else {
                missingSteps += 1
                if missingSteps == maximumSteps / 2 { scrollUp.toggle() }
            }
            guard step < maximumSteps else { break }
            let distance = min(250, (bottom - top) * 0.45)
            let middle = (top + bottom) / 2
            let startY = middle + (scrollUp ? distance / 2 : -distance / 2)
            let endY = middle + (scrollUp ? -distance / 2 : distance / 2)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: visible.midX - app.frame.minX, dy: startY - app.frame.minY))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: visible.midX - app.frame.minX, dy: endY - app.frame.minY)))
        }
        recordTaskInteraction(app, detail: "Cannot reveal \(element) in \(context); form=\(form.frame)")
        XCTFail("Task element could not be revealed in \(context): \(element)", file: file, line: line)
        return false
    }

    private func recordTaskInteraction(_ app: XCUIApplication, detail: String) {
        let tree = XCTAttachment(string: detail + "\n" + app.debugDescription)
        tree.name = "Scoped native interaction geometry and hierarchy"; tree.lifetime = .keepAlways; add(tree)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Scoped native interaction failure"; image.lifetime = .keepAlways; add(image)
    }
}
