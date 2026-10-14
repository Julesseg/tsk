import XCTest

extension XCTestCase {
    func setDateSwitch(_ identifier: String, to enabled: Bool, app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let tutorial = app.buttons["Continue"]
        if tutorial.exists, app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Speed up your typing")).firstMatch.exists {
            tutorial.tap()
        }
        let keyboardDone = app.buttons["dismiss-editor-keyboard"]
        if app.keyboards.firstMatch.exists {
            XCTAssertTrue(keyboardDone.waitForExistence(timeout: 5), file: file, line: line)
            keyboardDone.tap()
            let hidden = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.keyboards.firstMatch)
            XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed, "Keyboard still covers task dates", file: file, line: line)
        }
        let control = app.switches[identifier].firstMatch
        let form = app.collectionViews.firstMatch
        let screen = app.frame
        let navigationBottom = app.navigationBars.firstMatch.frame.maxY
        for _ in 0..<8 {
            let frame = control.frame
            if frame.minY.isFinite, frame.width > 0, frame.minY >= navigationBottom,
               frame.maxY < screen.maxY - 20, control.isHittable { break }
            form.swipeUp()
        }
        XCTAssertTrue(control.waitForExistence(timeout: 5), "Missing date switch: \(identifier)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(control.frame.minY, navigationBottom, file: file, line: line)
        XCTAssertLessThan(control.frame.maxY, screen.maxY - 20, file: file, line: line)
        let expected = enabled ? "1" : "0"
        if control.value as? String != expected {
            control.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        let state = NSPredicate(format: "value == %@", expected)
        let changed = expectation(for: state, evaluatedWith: control)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, "Date switch did not become \(enabled ? "enabled" : "disabled"): \(identifier)", file: file, line: line)
    }
}
