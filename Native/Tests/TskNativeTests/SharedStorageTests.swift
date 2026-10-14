import Foundation
import Testing
import TskCore
import TskNative

@Test func migratingToSharedStorageRetainsIdentityAttributesAndConnectionBeforeRetiringPrivateReplica() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let legacy = root.appendingPathComponent("private")
    let container = root.appendingPathComponent("group")
    let original = TaskManager(replica: TaskChampionReplica(directory: legacy))
    let task = try await original.create(TaskDraft(description: "Before upgrade", attributes: ["opaque": "retain", "annotation_1792015000": "Existing note", "café": "composed", "cafe\u{301}": "decomposed"]))
    let connection = try SyncConfiguration(serverURL: "https://sync.example.com", clientID: UUID(), encryptionSecret: "isolated migration fixture")
    try await SyncConfigurationStore(directory: legacy).save(connection)
    let shared = try TaskChampionSession.prepareShared(container: container, legacy: legacy)
    let reopened = try await TaskChampionSession.open(directory: shared)
    #expect(try await reopened.task(id: task.id) == task)
    #expect(try await SyncConfigurationStore(directory: shared).load() == connection)
    #expect(FileManager.default.fileExists(atPath: legacy.path))
    await #expect(throws: (any Error).self) { try await original.create(TaskDraft(description: "Must not fork the retired dataset")) }
    #expect(try TaskChampionSession.prepareShared(container: container, legacy: legacy) == shared)
}

@Test func invalidLegacyConnectionPreservesSourceAndNeverCreatesAnotherDataset() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let legacy = root.appendingPathComponent("private")
    let original = TaskManager(replica: TaskChampionReplica(directory: legacy))
    let task = try await original.create(TaskDraft(description: "Preserve on failure"))
    try Data("invalid configuration".utf8).write(to: legacy.appendingPathComponent("sync-configuration.json"))
    #expect(throws: (any Error).self) { try TaskChampionSession.prepareShared(container: root.appendingPathComponent("group"), legacy: legacy) }
    #expect(try await original.task(id: task.id) == task)
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("group/TaskChampion").path))
}
