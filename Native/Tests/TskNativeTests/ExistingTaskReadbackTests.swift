import Foundation
import Testing
import TskCore
import TskNative

@Test func existingStorageReadbackReturnsDurableValuesAndNeverCreatesMissingStorage() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let replica = TaskChampionReplica(directory: directory)
    await #expect(throws: (any Error).self) { try await replica.readExistingTasks() }
    #expect(!FileManager.default.fileExists(atPath: directory.path))
    let manager = TaskManager(replica: replica)
    let saved = try await manager.create(TaskDraft(description: "Native readback", attributes: ["scheduled": "1792231200", "due": "1792238400", "opaque": "retain bytes"]))
    let reopened = TaskChampionReplica(directory: directory)
    #expect(try await reopened.readExistingTasks() == [saved])
    #expect(try await manager.task(id: saved.id) == saved)
    let changed = try await manager.update(id: saved.id, changes: ["project": "Release", "priority": "H", "tag_next": ""])
    #expect(try await reopened.readExistingTasks() == [changed])
    let cleared = try await manager.update(id: saved.id, changes: ["project": nil, "priority": nil, "tag_next": nil])
    #expect(try await reopened.readExistingTasks() == [cleared])
    #expect(cleared.attributes["scheduled"] == saved.attributes["scheduled"])
    #expect(cleared.attributes["due"] == saved.attributes["due"])
    #expect(cleared.attributes["opaque"] == saved.attributes["opaque"])
}
