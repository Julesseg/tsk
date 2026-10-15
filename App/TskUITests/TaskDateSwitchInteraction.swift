import XCTest

extension XCTestCase {
    func setDateSwitch(_ identifier: String, to enabled: Bool, app: XCUIApplication, in containerID: String = "task-editor-form", keyboardDismissIdentifier: String = "dismiss-editor-keyboard", file: StaticString = #filePath, line: UInt = #line) {
        let tutorial = app.buttons["Continue"]
        if tutorial.exists, app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Speed up your typing")).firstMatch.exists {
            tutorial.tap()
        }
        let keyboardDone = app.buttons[keyboardDismissIdentifier]
        if app.keyboards.firstMatch.exists {
            XCTAssertTrue(keyboardDone.waitForExistence(timeout: 5), file: file, line: line)
            keyboardDone.tap()
            let hidden = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.keyboards.firstMatch)
            XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed, "Keyboard still covers task dates", file: file, line: line)
        }
        let control = app.switches[identifier].firstMatch
        guard revealTaskElement(control, in: containerID, app: app, file: file, line: line) else { return }
        let expected = enabled ? "1" : "0"
        if control.value as? String != expected {
            let thumb = control.switches.firstMatch
            if thumb.exists, thumb.isHittable { thumb.tap() }
            else { control.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
        }
        let state = NSPredicate(format: "value == %@", expected)
        let changed = expectation(for: state, evaluatedWith: control)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, "Date switch did not become \(enabled ? "enabled" : "disabled"): \(identifier)", file: file, line: line)
    }
    @discardableResult
    func revealTaskElement(_ element: XCUIElement, in containerID: String, app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let form = app.collectionViews[containerID].firstMatch
        guard form.waitForExistence(timeout: 5) else {
            XCTFail("Missing task form: \(containerID)", file: file, line: line)
            return false
        }
        let screen = app.frame
        let navigationBottom = app.navigationBars.allElementsBoundByIndex
            .filter { $0.exists && $0.isHittable && $0.frame.intersects(form.frame) }
            .map { $0.frame.maxY }.max() ?? form.frame.minY
        let viewport = form.frame.intersection(screen)
        let top = max(viewport.minY, navigationBottom)
        let bottom = viewport.maxY - 24
        var scrollUp = true
        var missingSteps = 0
        for step in 0...14 {
            if element.exists {
                let thumb = element.elementType == .switch ? element.switches.firstMatch : element
                let target = thumb.exists ? thumb : element
                let frame = target.frame
                if frame.minY.isFinite, frame.maxY.isFinite, frame.width > 0, frame.height > 0 {
                    if frame.minY >= top, frame.maxY <= bottom, target.isHittable { return true }
                    scrollUp = frame.minY >= top
                }
            } else {
                missingSteps += 1
                if missingSteps == 7 { scrollUp.toggle() }
            }
            guard step < 14 else { break }
            if scrollUp { form.swipeUp() } else { form.swipeDown() }
        }
        XCTFail("Task element could not be revealed in \(containerID): \(element)", file: file, line: line)
        return false
    }

}
