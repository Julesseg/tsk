#if canImport(AppIntents)
import AppIntents
import Foundation
import Testing
import TskCore
import TskNative

@available(macOS 13, iOS 16, *)
@Test func deleteIntentReturnsDurableRichEntityOfflineAndRepeatedDeletionPreservesHistory() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = try await TaskChampionSession.open(directory: directory)
    let original = try await manager.create(TaskDraft(description: "Delete offline", attributes: ["opaque": "keep", "annotation_10": "history", "project": "Travel", "tag_trip": "", "scheduled": "2000", "due": "3000", "wait": "1000"]))
    let completed = try await manager.complete(id: original.id)
    let entity = IntentTaskEntity(completed)
    let result = try await DeleteTaskIntent(task: entity, directory: directory).perform()
    #expect(result.value?.id == original.id)
    #expect(result.value?.status == "deleted")
    #expect(result.value?.project == "Travel")
    #expect(result.value?.tags == ["trip"])
    #expect(result.value?.scheduled == Date(timeIntervalSince1970: 2000))
    let reopened = try await TaskChampionSession.open(directory: directory)
    let deleted = try await reopened.task(id: original.id)
    #expect(deleted.status == "deleted")
    #expect(deleted.attributes["opaque"] == "keep")
    #expect(deleted.attributes["annotation_10"] == "history")
    #expect(deleted.attributes["end"] == completed.attributes["end"])
    _ = try await DeleteTaskIntent(task: entity, directory: directory).perform()
    #expect(try await reopened.task(id: original.id) == deleted)
    #expect(try await reopened.findTasks(FindTasksInput(status: .all)).isEmpty)
    await #expect(throws: TaskManagementError.unsupportedTaskKind) { try await CompleteTaskIntent(task: entity, directory: directory).perform() }
    let missing = IntentTaskEntity(TaskRecord(id: UUID(), attributes: [:]))
    await #expect(throws: TaskManagementError.taskNotFound(missing.id)) { try await DeleteTaskIntent(task: missing, directory: directory).perform() }
}
@available(macOS 13, iOS 16, *)
@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_SYNC_TEST_URL"] != nil))
func deleteIntentSynchronizesSoftDeletedIdentityAndHistoryToPeer() async throws {
    let environment = ProcessInfo.processInfo.environment
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let server = try #require(environment["TSK_SYNC_TEST_URL"])
    let client = try #require(environment["TSK_SYNC_TEST_CLIENT_ID"])
    let clientID = try #require(UUID(uuidString: client))
    let secret = try #require(environment["TSK_SYNC_TEST_SECRET"])
    let configuration = try SyncConfiguration(serverURL: server, clientID: clientID, encryptionSecret: secret)
    let directory = root.appendingPathComponent("app")
    let manager = try await TaskChampionSession.open(directory: directory)
    let original = try await manager.create(TaskDraft(description: "Peer deletion", attributes: ["opaque": "retain", "annotation_10": "history"]))
    _ = try await manager.synchronize(using: configuration)
    let peer = TaskManager(replica: TaskChampionReplica(directory: root.appendingPathComponent("peer")))
    _ = try await peer.synchronize(using: configuration)
    #expect(try await peer.task(id: original.id).status == "pending")
    _ = try await DeleteTaskIntent(task: IntentTaskEntity(original), directory: directory).perform()
    _ = try await manager.synchronize(using: configuration)
    _ = try await peer.synchronize(using: configuration)
    let record = try await peer.task(id: original.id)
    #expect(record.status == "deleted")
    #expect(record.attributes["opaque"] == "retain")
    #expect(record.attributes["annotation_10"] == "history")
    #expect(try await peer.findTasks(FindTasksInput(status: .all)).isEmpty)
}
#endif
