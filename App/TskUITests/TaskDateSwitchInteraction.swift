import XCTest

@MainActor
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
        recordTaskSwitchInteraction(row: control, selected: control.switches.firstMatch.exists ? control.switches.firstMatch : control, phase: "after", app: app, includeHierarchy: result != .completed)
        XCTAssertEqual(result, .completed, "Date switch did not become \(enabled ? "enabled" : "disabled"): \(identifier)", file: file, line: line)
    }

    func recordTaskSwitchInteraction(row: XCUIElement, selected: XCUIElement, phase: String, app: XCUIApplication, includeHierarchy: Bool = false) {
        guard ProcessInfo.processInfo.environment["TSK_UI_ISOLATED_SIMULATOR"] == "1" else { return }
        do {
            let rowSnapshot = try row.snapshot()
            let selectedSnapshot = try selected.snapshot()
            let frame = selectedSnapshot.frame
            var metadata = "phase=\(phase)\nrowIdentifier=\(rowSnapshot.identifier)\nrowValue=\(String(describing: rowSnapshot.value))\nselectedIdentifier=\(selectedSnapshot.identifier)\nselectedValue=\(String(describing: selectedSnapshot.value))\nenabled=\(selectedSnapshot.isEnabled)\nhittable=\(selected.isHittable)\nframe=\(frame)\nappFrame=\(app.frame)\nrequestedTap=\(frame.midX),\(frame.midY)"
            if includeHierarchy { metadata += "\nrowHierarchy=\(row.debugDescription)" }
            let attachment = XCTAttachment(string: metadata)
            attachment.name = "Actual selected switch \(phase) metadata"
            attachment.lifetime = .keepAlways
            add(attachment)
        } catch {
            recordTaskInteraction(app, detail: "Switch diagnostic snapshot unavailable for \(phase): \(error)")
        }
    }

    func tapTaskControl(_ element: XCUIElement, app: XCUIApplication, deadline: TimeInterval? = nil, beforeSample: ((TimeInterval) -> Void)? = nil, file: StaticString = #filePath, line: UInt = #line) {
        activateTaskControl(element, app: app, deadline: deadline, beforeSample: beforeSample, file: file, line: line) {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1)
        }
    }

    func tapTaskMenuItem(_ element: XCUIElement, app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        activateTaskControl(element, app: app, file: file, line: line) { element.tap() }
    }

    private func activateTaskControl(_ element: XCUIElement, app: XCUIApplication, deadline: TimeInterval? = nil, beforeSample: ((TimeInterval) -> Void)? = nil, file: StaticString, line: UInt, action: () -> Void) {
        var lastSampleReads = "not sampled"
        let attempt = TaskControlReadinessAttempt(now: { ProcessInfo.processInfo.systemUptime }, deadline: deadline, beforeSample: beforeSample) {
            var sample = TaskControlReadinessSample(exists: nil)
            var reads: [String] = []
            defer { lastSampleReads = reads.joined(separator: ", ") }
            func measured<T>(_ name: String, read: () throws -> T) rethrows -> T {
                let started = ProcessInfo.processInfo.systemUptime
                defer { reads.append("\(name)=\(ProcessInfo.processInfo.systemUptime - started)s") }
                return try read()
            }
            do {
                let snapshot = try measured("element.snapshot") { try element.snapshot() }
                sample.exists = true
                sample.enabled = snapshot.isEnabled
                sample.elementFrame = snapshot.frame
                guard snapshot.isEnabled else { return sample }
                sample.hittable = measured("element.isHittable") { element.isHittable }
                guard sample.hittable == true else { return sample }
                let application = try measured("app.snapshot") { try app.snapshot() }
                sample.appFrame = application.frame
                sample.appWindowFrames = application.children.filter { $0.elementType == .window }.map { $0.frame }
            } catch {
                sample.snapshotError = String(describing: error)
            }
            return sample
        }
        var result: XCTWaiter.Result?
        let completed = attempt.waitUntilReady { timeout, evaluate in
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in evaluate() }, object: nil)
            result = XCTWaiter.wait(for: [ready], timeout: timeout)
            return result == .completed
        }
        guard attempt.finish(waitCompleted: completed, perform: { _ in
            action()
        }) else {
            let waiter = result.map { String(describing: $0) } ?? "not entered"
            recordTaskInteraction(app, detail: "Cannot activate \(element); waiter=\(waiter) \(attempt.diagnostic) lastSampleReads=[\(lastSampleReads)]")
            XCTFail("Control has no valid visible hit area: \(element); \(attempt.diagnostic) lastSampleReads=[\(lastSampleReads)]", file: file, line: line)
            return
        }
    }

    func focusTaskText(_ element: XCUIElement, app: XCUIApplication, beforeSample: ((TimeInterval) -> Void)? = nil, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), file: file, line: line)
        tapTaskControl(element, app: app, beforeSample: beforeSample, file: file, line: line)
        guard let beforeSample else {
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Text input has no keyboard: \(element)", file: file, line: line)
            return
        }
        let deadline = ProcessInfo.processInfo.systemUptime + TaskControlReadinessPolicy.accessibilityAdmissionTimeout
        func sample() -> Bool {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return false }
            beforeSample(deadline)
            guard ProcessInfo.processInfo.systemUptime < deadline else { return false }
            return app.keyboards.firstMatch.exists && ProcessInfo.processInfo.systemUptime < deadline
        }
        var ready = sample()
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        if !ready, remaining > 0 {
            let keyboard = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in sample() }, object: nil)
            ready = XCTWaiter.wait(for: [keyboard], timeout: remaining) == .completed && ProcessInfo.processInfo.systemUptime < deadline
        }
        XCTAssertTrue(ready, "Text input has no keyboard: \(element)", file: file, line: line)
    }

    func replaceTaskText(_ element: XCUIElement, with value: String, app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        focusTaskText(element, app: app, file: file, line: line)
        let previous = element.value as? String ?? ""
        if !previous.isEmpty && previous != element.placeholderValue {
            element.press(forDuration: 1.1)
            let started = ProcessInfo.processInfo.systemUptime
            let deadline = started + 5
            let menu = app.menuItems["Select All"]
            let button = app.buttons["Select All"]
            var selected: XCUIElement?
            func sample() -> Bool {
                guard ProcessInfo.processInfo.systemUptime < deadline else { return false }
                if menu.exists { selected = menu; return true }
                guard ProcessInfo.processInfo.systemUptime < deadline else { return false }
                if button.exists { selected = button; return true }
                return false
            }
            let immediate = sample()
            var result: XCTWaiter.Result?
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            if !immediate, remaining > 0 {
                let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in sample() }, object: nil)
                result = XCTWaiter.wait(for: [ready], timeout: remaining)
            }
            let elapsed = ProcessInfo.processInfo.systemUptime - started
            guard immediate || result == .completed, elapsed < 5, let selectAll = selected else {
                let reason = elapsed >= 5 ? "deadline expired" : selected == nil ? "native menu absent" : "waiter did not complete"
                let waiter = result.map { String(describing: $0) } ?? "not entered"
                recordTaskInteraction(app, detail: "Native Select All was not ready for \(element); reason=\(reason) immediate=\(immediate) waiter=\(waiter) elapsed=\(elapsed)s")
                XCTFail("Text replacement has no ready native Select All control", file: file, line: line)
                return
            }
            selectAll.tap()
        }
        element.typeText(XCUIKeyboardKey.delete.rawValue)
        let cleared = element.value as? String ?? ""
        guard cleared.isEmpty || cleared == element.placeholderValue else {
            recordTaskInteraction(app, detail: "Replacement did not clear \(element)")
            XCTFail("Text replacement did not clear the previous value: \(cleared)", file: file, line: line)
            return
        }
        if !value.isEmpty { element.typeText(value) }
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        func matchesReplacement() -> Bool {
            let current = element.value as? String ?? ""
            return current == value || value.isEmpty && current == element.placeholderValue
        }
        var acknowledged = matchesReplacement() && ProcessInfo.processInfo.systemUptime < deadline
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        if !acknowledged, remaining > 0 {
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                ProcessInfo.processInfo.systemUptime < deadline && matchesReplacement() && ProcessInfo.processInfo.systemUptime < deadline
            }, object: nil)
            acknowledged = XCTWaiter.wait(for: [ready], timeout: remaining) == .completed && ProcessInfo.processInfo.systemUptime < deadline
        }
        XCTAssertTrue(acknowledged, "Text replacement value did not settle within five seconds", file: file, line: line)
        XCTAssertTrue((element.value as? String ?? "") == value || value.isEmpty && (element.value as? String) == element.placeholderValue, "Text replacement value differs", file: file, line: line)
    }

    @discardableResult
    func revealTaskElement(_ element: XCUIElement, in containerID: String, app: XCUIApplication, initialScrollUp: Bool = true, maximumSteps: Int = 14, bottomInset: XCUIElement? = nil, requireFullVisibility: Bool = false, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        revealTaskElement(element, in: app.collectionViews[containerID].firstMatch, app: app, initialScrollUp: initialScrollUp, maximumSteps: maximumSteps, context: containerID, bottomInset: bottomInset, requireFullVisibility: requireFullVisibility, file: file, line: line)
    }

    @discardableResult
    func revealTaskElement(_ element: XCUIElement, in form: XCUIElement, app: XCUIApplication, initialScrollUp: Bool = true, maximumSteps: Int = 14, context: String = "native settings list", bottomInset: XCUIElement? = nil, requireFullVisibility: Bool = false, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard form.waitForExistence(timeout: 5) else {
            recordTaskInteraction(app, detail: "Missing form \(context)")
            XCTFail("Missing task form: \(context)", file: file, line: line)
            return false
        }
        var direction = TaskRevealScrollDirection(initialScrollUp: initialScrollUp)
        for step in 0...maximumSteps {
            let formFrame = form.frame
            let appFrame = app.frame
            let visible = formFrame.intersection(appFrame)
            let navigationBottom = app.navigationBars.allElementsBoundByIndex.compactMap { item -> CGFloat? in
                guard item.exists, item.isHittable else { return nil }
                let frame = item.frame
                return frame.intersection(visible).width > visible.width / 2 && frame.maxY <= visible.minY + 140 ? frame.maxY : nil
            }.max() ?? visible.minY
            let pinnedIDs = ["continuous-reminders-status", "continuous-reminders-paused", "continuous-reminders-result", "continuous-reminders-error", "continuous-reminders-stop", "continuous-reminders-resume-fixture", "continuous-reminders-edit-fixture", "continuous-reminders-fixture-changed", "task-editor-error", "series-metadata-error", "transition-error", "annotation-editor-error", "advanced-attributes-error", "filter-error"]
            let pinnedBottom = app.descendants(matching: .any).matching(NSPredicate(format: "identifier IN %@", pinnedIDs)).allElementsBoundByIndex.compactMap { item -> CGFloat? in
                guard item.exists, item.isHittable else { return nil }
                let frame = item.frame
                return frame.intersects(visible) ? frame.maxY : nil
            }.max() ?? visible.minY
            let top = max(visible.minY, navigationBottom, pinnedBottom) + 8
            let keyboard = app.keyboards.firstMatch
            let insetFrame = bottomInset.flatMap { $0.exists ? $0.frame : nil }
            let body = TaskRevealVisibleBody(visibleFrame: visible, top: top, keyboardFrame: keyboard.exists ? keyboard.frame : nil, bottomInsetFrame: insetFrame)
            let bottom = body.bottom
            guard visible.width > 0, bottom - top > 60 else { break }
            var targetMidY: CGFloat?
            if element.exists {
                let thumb = element.elementType == .switch ? element.switches.firstMatch : element
                let target = thumb.exists ? thumb : element
                let frame = target.frame
                if frame.minY.isFinite, frame.maxY.isFinite, frame.width > 0, frame.height > 0 {
                    let targetVisible = requireFullVisibility ? body.contains(frame: frame) : body.contains(midY: frame.midY)
                    if targetVisible, target.isHittable { return true }
                    targetMidY = body.scrollTargetY(for: frame, requireFullVisibility: requireFullVisibility)
                }
            }
            let scrollUp = direction.update(targetMidY: targetMidY, bottom: bottom)
            guard step < maximumSteps else { break }
            let distance = min(250, (bottom - top) * 0.45)
            let middle = (top + bottom) / 2
            let startY = middle + (scrollUp ? distance / 2 : -distance / 2)
            let endY = middle + (scrollUp ? -distance / 2 : distance / 2)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: visible.midX - appFrame.minX, dy: startY - appFrame.minY))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: visible.midX - appFrame.minX, dy: endY - appFrame.minY)))
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
