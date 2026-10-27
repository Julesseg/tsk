import XCTest

enum TaskTextSelection {
    case editMenu
    case commandA
}

private enum TaskControlKeyboardRequirement {
    case none, dismissal, visible
}

@MainActor
extension XCTestCase {
    func taskSnapshot(_ identifier: String, type: XCUIElement.ElementType? = nil, in root: any XCUIElementSnapshot) -> (any XCUIElementSnapshot)? {
        var pending: [any XCUIElementSnapshot] = [root]
        while let snapshot = pending.popLast() {
            if snapshot.identifier == identifier, type == nil || snapshot.elementType == type { return snapshot }
            pending.append(contentsOf: snapshot.children)
        }
        return nil
    }

    func activateSavedWorkspaceView(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "saved-view-")).firstMatch
        guard revealTaskElement(saved, in: "views-list", app: app, file: file, line: line) else { return }
        let id = String(saved.identifier.dropFirst("saved-view-".count))
        let add = app.buttons["activate-custom-" + id]
        if add.exists {
            if !add.isEnabled {
                let remove = app.buttons["deactivate-unfinished"]
                guard revealTaskElement(remove, in: "views-list", app: app, initialScrollUp: false, file: file, line: line) else { return }
                tapTaskControl(remove, app: app, file: file, line: line)
            }
            guard revealTaskElement(add, in: "views-list", app: app, file: file, line: line) else { return }
            tapTaskControl(add, app: app, file: file, line: line)
        }
        guard revealTaskElement(saved, in: "views-list", app: app, initialScrollUp: false, file: file, line: line) else { return }
        let title = saved.label
        tapTaskControl(saved, app: app, file: file, line: line)
        XCTAssertTrue(app.collectionViews["views-list"].waitForNonExistence(timeout: 10), file: file, line: line)
        let tab = app.tabBars.buttons[title]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertTrue(tab.isSelected, file: file, line: line)
    }

    func openSavedViewOptions(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let options = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "view-options-")).firstMatch
        guard revealTaskElement(options, in: "views-list", app: app, file: file, line: line) else { return }
        tapTaskControl(options, app: app, file: file, line: line)
    }

    @discardableResult
    func revealWorkspaceSetting(_ identifier: String, app: XCUIApplication, initialScrollUp: Bool = true, beforeSample: ((TimeInterval) -> Void)? = nil, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let settings = app.collectionViews["workspace-settings-list"]
        if !settings.exists {
            let button = app.buttons["workspace-settings"]
            XCTAssertTrue(button.waitForExistence(timeout: 15), file: file, line: line)
            tapTaskControl(button, app: app, beforeSample: beforeSample, file: file, line: line)
        }
        return revealTaskElement(app.buttons[identifier], in: "workspace-settings-list", app: app, initialScrollUp: initialScrollUp, file: file, line: line)
    }

    func openWorkspaceSetting(_ identifier: String, app: XCUIApplication, beforeSample: ((TimeInterval) -> Void)? = nil, file: StaticString = #filePath, line: UInt = #line) {
        guard revealWorkspaceSetting(identifier, app: app, beforeSample: beforeSample, file: file, line: line) else { return }
        tapTaskControl(app.buttons[identifier], app: app, beforeSample: beforeSample, file: file, line: line)
    }

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
        if keyboardDone.exists || app.keyboards.firstMatch.exists {
            XCTAssertTrue(keyboardDone.waitForExistence(timeout: 5), file: file, line: line)
            tapTaskControlAtCenter(keyboardDone, app: app, file: file, line: line)
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "Keyboard still covers task dates", file: file, line: line)
        }
        let control = app.collectionViews[containerID].switches[identifier].firstMatch
        guard revealTaskElement(control, in: containerID, app: app, file: file, line: line) else { return }
        if !TaskSwitchValue.matches(control.value, enabled: enabled) {
            let thumb = control.switches.firstMatch
            let selected = thumb.exists ? thumb : control
            recordTaskSwitchInteraction(row: control, selected: selected, phase: "before", app: app)
            tapTaskControlAtCenter(selected, app: app, file: file, line: line)
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        var lastSample = "not sampled"
        func changed() -> Bool {
            let started = ProcessInfo.processInfo.systemUptime
            guard started < deadline else { return false }
            do {
                let form = try app.collectionViews[containerID].firstMatch.snapshot()
                guard let snapshot = taskSnapshot(identifier, type: .switch, in: form) else {
                    lastSample = "Switch absent from form snapshot"
                    return false
                }
                let value = snapshot.value
                let matches = TaskSwitchValue.matches(value, enabled: enabled)
                let finished = ProcessInfo.processInfo.systemUptime
                let accepted = finished < deadline && matches
                let type = value.map { String(reflecting: Swift.type(of: $0)) } ?? "nil"
                lastSample = "value=\(String(describing: value)); type=\(type); readSeconds=\(finished - started); remainingSeconds=\(deadline - finished)"
                return accepted
            } catch {
                lastSample = "snapshotError=\(error); readSeconds=\(ProcessInfo.processInfo.systemUptime - started)"
                return false
            }
        }
        var acknowledged = changed()
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        if !acknowledged, remaining > 0 {
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in changed() }, object: nil)
            acknowledged = XCTWaiter.wait(for: [ready], timeout: remaining) == .completed && ProcessInfo.processInfo.systemUptime < deadline
        }
        recordTaskSwitchInteraction(row: control, selected: control.switches.firstMatch.exists ? control.switches.firstMatch : control, phase: "after", app: app, includeHierarchy: !acknowledged)
        XCTAssertTrue(acknowledged, "Date switch did not become \(enabled ? "enabled" : "disabled"): \(identifier); \(lastSample)", file: file, line: line)
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
        activateTaskControl(element, app: app, deadline: deadline, beforeSample: beforeSample, file: file, line: line) { _ in
            element.tap()
        }
    }

    func tapTaskControlAtCenter(_ element: XCUIElement, app: XCUIApplication, requiresVisibleKeyboard: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        activateTaskControl(element, app: app, keyboardRequirement: requiresVisibleKeyboard ? .visible : .dismissal, file: file, line: line) { _ in
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    func tapTaskButton(_ element: XCUIElement, app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        activateTaskControl(element, app: app, file: file, line: line) { _ in element.tap() }
    }

    func tapTaskMenuItem(_ element: XCUIElement, app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        tapTaskButton(element, app: app, file: file, line: line)
    }

    func tapTaskPickerOption(_ label: String, options: [String], app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = ProcessInfo.processInfo.systemUptime + TaskControlReadinessPolicy.accessibilityAdmissionTimeout
        var previous: TaskNativeMenuOptionGeometry?
        var lastSample = "not sampled"
        func sample() -> Bool {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return false }
            do {
                let application = try app.snapshot()
                var pending: [(any XCUIElementSnapshot, [CGRect])] = [(application, [])]
                var candidates: [TaskNativeMenuOptionGeometry] = []
                var matches = 0
                while let (snapshot, ancestors) = pending.popLast() {
                    let frames = ancestors + [snapshot.frame]
                    if snapshot.elementType == .button, snapshot.label == label { matches += 1 }
                    if snapshot.elementType == .collectionView {
                        let choices = snapshot.children.filter { $0.elementType == .cell }.flatMap { cell in
                            cell.children.filter { $0.elementType == .button }.map { (cell.frame, $0) }
                        }
                        if choices.map({ $0.1.label }) == options {
                            for (rowFrame, button) in choices where button.label == label && button.isEnabled {
                                candidates.append(TaskNativeMenuOptionGeometry(frame: button.frame, ancestorFrames: frames + [rowFrame]))
                            }
                        }
                    }
                    pending.append(contentsOf: snapshot.children.map { ($0, frames) })
                }
                lastSample = "matchingButtons=\(matches) matchingMenus=\(candidates.count) geometry=\(String(describing: candidates.first))"
                guard ProcessInfo.processInfo.systemUptime < deadline, matches == 1, candidates.count == 1,
                      let current = candidates.first, current.isVisible else { previous = nil; return false }
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
            recordTaskInteraction(app, detail: "Native picker option has no stable visible menu row: \(label); \(lastSample)")
            XCTFail("Native picker menu did not settle: \(label); \(lastSample)", file: file, line: line)
            return
        }
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func activateTaskControl(_ element: XCUIElement, app: XCUIApplication, deadline: TimeInterval? = nil, beforeSample: ((TimeInterval) -> Void)? = nil, keyboardRequirement: TaskControlKeyboardRequirement = .none, file: StaticString, line: UInt, action: (TaskControlReadinessGeometry) -> Void) {
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
                if keyboardRequirement == .visible || keyboardRequirement == .dismissal && snapshot.identifier.hasPrefix("dismiss-") {
                    let keyboard = try? measured("keyboard.snapshot") { try app.keyboards.firstMatch.snapshot() }
                    sample.keyboardFrames = keyboard.map { [$0.frame] } ?? []
                    if let keyboard, !keyboard.frame.isEmpty,
                       let assistant = self.taskSnapshot("inputAssistantView", in: application) {
                        sample.keyboardFrames?.append(assistant.frame)
                    }
                    print("Keyboard layout sample: id=\(snapshot.identifier) \(sample.diagnostic)")
                }
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
        guard attempt.finish(waitCompleted: completed, perform: action) else {
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

    func replaceTaskText(_ element: XCUIElement, with value: String, app: XCUIApplication, selection: TaskTextSelection = .editMenu, file: StaticString = #filePath, line: UInt = #line) {
        focusTaskText(element, app: app, file: file, line: line)
        let previous = element.value as? String ?? ""
        if !previous.isEmpty && previous != element.placeholderValue {
            switch selection {
            case .editMenu:
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
            case .commandA:
                element.typeKey("a", modifierFlags: .command)
            }
        }
        element.typeText(XCUIKeyboardKey.delete.rawValue)
        guard assertTaskText(element, equals: "", file: file, line: line) else {
            recordTaskInteraction(app, detail: "Replacement did not clear \(element)")
            return
        }
        if !value.isEmpty { element.typeText(value) }
        assertTaskText(element, equals: value, file: file, line: line)
    }

    @discardableResult
    func assertTaskText(_ element: XCUIElement, equals value: String, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        func matchesValue() -> Bool {
            let current = element.value as? String ?? ""
            return current == value || value.isEmpty && current == element.placeholderValue
        }
        var acknowledged = matchesValue() && ProcessInfo.processInfo.systemUptime < deadline
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        if !acknowledged, remaining > 0 {
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                ProcessInfo.processInfo.systemUptime < deadline && matchesValue() && ProcessInfo.processInfo.systemUptime < deadline
            }, object: nil)
            acknowledged = XCTWaiter.wait(for: [ready], timeout: remaining) == .completed && ProcessInfo.processInfo.systemUptime < deadline
        }
        XCTAssertTrue(acknowledged, "Text value did not settle within five seconds", file: file, line: line)
        let matches = matchesValue()
        XCTAssertTrue(matches, "Text value differs", file: file, line: line)
        return acknowledged && matches
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
        let pinnedIDs: Set<String> = ["continuous-reminders-status", "continuous-reminders-paused", "continuous-reminders-result", "continuous-reminders-error", "continuous-reminders-stop", "continuous-reminders-resume-fixture", "continuous-reminders-edit-fixture", "continuous-reminders-fixture-changed", "task-action-banner", "task-editor-error", "series-metadata-error", "transition-error", "annotation-editor-error", "advanced-attributes-error", "filter-error"]
        for step in 0...maximumSteps {
            let application: any XCUIElementSnapshot
            do { application = try app.snapshot() }
            catch {
                XCTFail("Cannot snapshot native reveal geometry in \(context): \(error)", file: file, line: line)
                return false
            }
            var snapshots = [application]
            var pending = Array(application.children.reversed())
            while let snapshot = pending.popLast() {
                snapshots.append(snapshot)
                pending.append(contentsOf: snapshot.children.reversed())
            }
            let formFrame = form.frame
            let appFrame = application.frame
            let visible = formFrame.intersection(appFrame)
            let navigationBottom = app.navigationBars.allElementsBoundByIndex.compactMap { item -> CGFloat? in
                guard item.exists, item.isHittable else { return nil }
                let frame = item.frame
                return frame.intersection(visible).width > visible.width / 2 && frame.maxY <= visible.minY + 140 ? frame.maxY : nil
            }.max() ?? visible.minY
            var pinnedQueries: Set<String> = []
            let pinnedBottom = snapshots.filter { pinnedIDs.contains($0.identifier) }.compactMap { snapshot -> CGFloat? in
                guard pinnedQueries.insert("\(snapshot.elementType.rawValue):\(snapshot.identifier)").inserted else { return nil }
                return app.descendants(matching: snapshot.elementType).matching(identifier: snapshot.identifier).allElementsBoundByIndex.compactMap { item -> CGFloat? in
                    guard item.exists, item.isHittable else { return nil }
                    let frame = item.frame
                    return frame.intersects(visible) ? frame.maxY : nil
                }.max()
            }.max() ?? visible.minY
            let top = max(visible.minY, navigationBottom, pinnedBottom) + 8
            let keyboardFrame = snapshots.first { $0.elementType == .keyboard }?.frame
            let insetFrame = bottomInset.flatMap { $0.exists ? $0.frame : nil }
            let tabBarFrame = app.tabBars.allElementsBoundByIndex.compactMap { item -> CGRect? in
                guard item.exists, item.isHittable else { return nil }
                return TaskRevealVisibleBody.lowerInsetFrame(item.frame, in: visible)
            }.min { $0.minY < $1.minY }
            let body = TaskRevealVisibleBody(visibleFrame: visible, top: top, keyboardFrame: keyboardFrame, bottomInsetFrame: insetFrame, tabBarFrame: tabBarFrame)
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
