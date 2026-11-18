#if DEBUG
import Foundation
import TskNative
import TskCore

func runTaskAutomationFixture() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let action = environment["TSK_TEST_INTENT_ACTION"] else { return }
    guard let rawID = environment["TSK_TEST_INTENT_TARGET_UUID"], let id = UUID(uuidString: rawID) else { throw CocoaError(.coderInvalidValue) }
    let directory = try TaskChampionSession.directory(testName: environment["TSK_TEST_REPLICA_NAME"])
    let manager = try await TaskChampionSession.open(directory: directory)
    let entity = IntentTaskEntity(try await manager.task(id: id))
    if action == "complete" {
        _ = try await CompleteTaskIntent(task: entity).perform()
    } else if action == "delete" {
        _ = try await DeleteTaskIntent(task: entity).perform()
    } else {
        guard let rawDate = environment["TSK_TEST_INTENT_DATE"], let timestamp = Double(rawDate), ["planned", "deadline"].contains(action) else { throw CocoaError(.coderInvalidValue) }
        _ = try await ModifyTaskIntent(task: entity, scheduled: action == "planned" ? Date(timeIntervalSince1970: timestamp) : nil, deadline: action == "deadline" ? Date(timeIntervalSince1970: timestamp) : nil).perform()
    }
}
#endif

#if DEBUG
func installNavigationFixture() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard environment["TSK_TEST_NAVIGATION_FIXTURE"] == "1", let replicaName = environment["TSK_TEST_REPLICA_NAME"], UUID(uuidString: replicaName) != nil else { return }
    let directory = try TaskChampionSession.directory(testName: replicaName)
    let manager = try await TaskChampionSession.open(directory: directory)
    if try await manager.tasks().isEmpty {
        _ = try await manager.create(TaskDraft(description: "Navigation task", attributes: ["project": "Work.Travel"]))
        _ = try await manager.create(TaskDraft(description: "Second task"))
        let done = try await manager.create(TaskDraft(description: "Completed navigation task"))
        _ = try await manager.complete(id: done.id)
    }
}
#endif
