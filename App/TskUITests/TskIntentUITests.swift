import XCTest

final class TskIntentUITests: XCTestCase {
    @MainActor func testNativeIntentCaptureIsVisibleAndSurvivesAppRelaunch() {
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_INTENT_DESCRIPTION"] = "Captured through native intent"
        app.launch()
        XCTAssertTrue(app.staticTexts["Captured through native intent"].waitForExistence(timeout: 20))
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "TSK_TEST_INTENT_DESCRIPTION")
        app.launch()
        XCTAssertTrue(app.staticTexts["Captured through native intent"].waitForExistence(timeout: 15))
        app.buttons["task-shortcuts"].tap()
        XCTAssertTrue(app.navigationBars["Shortcuts and Siri"].waitForExistence(timeout: 5))
    }
}
