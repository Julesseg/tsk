import XCTest

final class TskIntentUITests: XCTestCase {
    @MainActor func testNativeIntentCaptureIsVisibleAndSurvivesAppRelaunch() {
        let app = taskTestApplication()
        app.launchEnvironment["TSK_TEST_REPLICA_NAME"] = UUID().uuidString
        app.launchEnvironment["TSK_TEST_INTENT_DESCRIPTION"] = "Captured through native intent"
        app.launch()
        selectAllTasks(app)
        XCTAssertTrue(taskRow(named: "Captured through native intent", app: app).waitForExistence(timeout: 20))
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "TSK_TEST_INTENT_DESCRIPTION")
        app.launch()
        selectAllTasks(app)
        XCTAssertTrue(taskRow(named: "Captured through native intent", app: app).waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["task-shortcuts"].exists)
    }
}
