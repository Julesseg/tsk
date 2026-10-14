import Foundation
import Testing
import TskCore

@Test func failedSynchronizationKeepsDurableLocalTaskAvailable() async throws {
    let replica = SynchronizingTestReplica()
    let manager = TaskManager(replica: replica)
    let saved = try await manager.create(TaskDraft(description: "Offline task", attributes: ["customOpaque": "retain"]))
    let config = try SyncConfiguration(serverURL: "https://tasks.example.test", clientID: UUID(), encryptionSecret: "isolated-secret")
    await #expect(throws: SynchronizationError.failed("Server unavailable")) {
        try await manager.synchronize(using: config)
    }
    #expect(try await manager.task(id: saved.id) == saved)
}

private actor SynchronizingTestReplica: TaskSynchronizingReplica {
    var records: [UUID: TaskRecord] = [:]
    func tasks() async throws -> [TaskRecord] { Array(records.values) }
    func create(id: UUID, attributes: [String: String]) async throws -> TaskRecord {
        let record = TaskRecord(id: id, attributes: attributes)
        records[id] = record
        return record
    }
    func update(id: UUID, changes: [String: String?]) async throws -> TaskRecord {
        guard var record = records[id] else { throw TaskManagementError.taskNotFound(id) }
        for (key, value) in changes { record.attributes[key] = value }
        records[id] = record
        return record
    }
    func synchronize(using configuration: SyncConfiguration) async throws {
        throw SynchronizationError.failed("Server unavailable")
    }
}
