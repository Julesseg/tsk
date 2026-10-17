#if DEBUG
import Foundation
import TskNative

func runTaskAutomationFixture() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let action = environment["TSK_TEST_INTENT_ACTION"] else { return }
    guard let rawID = environment["TSK_TEST_INTENT_TARGET_UUID"], let id = UUID(uuidString: rawID) else { throw CocoaError(.coderInvalidValue) }
    let directory = try TaskChampionSession.directory(testName: environment["TSK_TEST_REPLICA_NAME"])
    let manager = try await TaskChampionSession.open(directory: directory)
    let entity = IntentTaskEntity(try await manager.task(id: id))
    if action == "complete" {
        _ = try await CompleteTaskIntent(task: entity).perform()
    } else {
        guard let rawDate = environment["TSK_TEST_INTENT_DATE"], let timestamp = Double(rawDate), ["planned", "deadline"].contains(action) else { throw CocoaError(.coderInvalidValue) }
        _ = try await RescheduleTaskIntent(task: entity, role: action == "planned" ? .plannedDay : .deadline, date: Date(timeIntervalSince1970: timestamp)).perform()
    }
}
#endif
