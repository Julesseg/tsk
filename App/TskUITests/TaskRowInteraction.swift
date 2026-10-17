import XCTest

extension XCTestCase {
    @MainActor func taskTestApplication() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TSK_UI_DISABLE_ANIMATIONS"] = "1"
        app.launchEnvironment["TSK_UI_TEST_SESSION"] = UUID().uuidString
        return app
    }

    @MainActor func resetOwnedReminderAuthorization(_ app: XCUIApplication, token: String, stage: String) {
        guard ProcessInfo.processInfo.environment["TSK_UI_ISOLATED_SIMULATOR"] == "1", UUID(uuidString: token) != nil else {
            XCTFail("Reminders authorization timeline requires the owned isolated fixture")
            return
        }
        let started = Date().timeIntervalSince1970
        app.resetAuthorizationStatus(for: .reminders)
        let evidence: [String: Any] = ["token": token, "stage": stage, "started": started, "returned": Date().timeIntervalSince1970,
                                       "testProcessID": ProcessInfo.processInfo.processIdentifier]
        let data = try? JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(string: data.map { String(decoding: $0, as: UTF8.self) } ?? "Reset timeline encoding failed")
        attachment.name = "Owned Reminders authorization reset timeline \(stage)"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func taskRow(named description: String, app: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(format: "identifier MATCHES %@ AND (label == %@ OR label BEGINSWITH %@)", "task-[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}", description, description + ", ")
        return app.buttons.matching(predicate).firstMatch
    }
}
