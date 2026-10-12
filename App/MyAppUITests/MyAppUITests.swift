import XCTest

// Smoke test proving the XCUITest lane works end-to-end (build, launch,
// query). Grow this suite with your app's acceptance-level UI behaviors;
// keep the logic itself in Core where `swift test` covers it fast.
final class MyAppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAppLaunchesAndShowsGreeting() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["greeting"].waitForExistence(timeout: 10))
    }
}
