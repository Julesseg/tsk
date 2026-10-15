import XCTest

extension XCTestCase {
    func taskRow(named description: String, app: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(format: "identifier MATCHES %@ AND (label == %@ OR label BEGINSWITH %@)", "task-[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}", description, description + ", ")
        return app.buttons.matching(predicate).firstMatch
    }
}
