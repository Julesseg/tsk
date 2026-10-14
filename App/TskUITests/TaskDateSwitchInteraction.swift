import XCTest

extension XCTestCase {
    func setDateSwitch(_ identifier: String, to enabled: Bool, app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let tutorial = app.buttons["Continue"]
        if tutorial.exists, app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Speed up your typing")).firstMatch.exists {
            tutorial.tap()
        }
        let control = app.switches[identifier].firstMatch
        for _ in 0..<6 where !control.isHittable { app.swipeUp() }
        XCTAssertTrue(control.waitForExistence(timeout: 5), "Missing date switch: \(identifier)", file: file, line: line)
        let expected = enabled ? "1" : "0"
        if control.value as? String != expected {
            control.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        let state = NSPredicate(format: "value == %@", expected)
        let changed = expectation(for: state, evaluatedWith: control)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, "Date switch did not become \(enabled ? "enabled" : "disabled"): \(identifier)", file: file, line: line)
    }
}
