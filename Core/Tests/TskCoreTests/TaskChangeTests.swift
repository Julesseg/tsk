import Foundation
import Testing
import TskCore

@Test func successfulDurableLocalOnlyMutationsPublishChangesButRejectedWritesDoNot() async throws {
    let manager = TaskManager(replica: TestReplica())
    let initial = try await manager.changeVersion()
    await #expect(throws: TaskManagementError.emptyDescription) { try await manager.create(TaskDraft()) }
    #expect(try await manager.changeVersion() == initial)
    let task = try await manager.create(TaskDraft(description: "Local change", attributes: ["foreign": "preserved"]))
    let created = try await manager.changeVersion()
    #expect(created.tasks != initial.tasks)
    #expect(created.views == initial.views)
    #expect(created.schema == initial.schema)
    _ = try await manager.complete(id: task.id)
    #expect(try await manager.changeVersion().tasks != created.tasks)
    #expect(try await manager.task(id: task.id).attributes["foreign"] == "preserved")
}

@Test func receivedDurableChangesDistinguishSuccessfulAndPartiallyFailedSynchronization() async throws {
    for fails in [false, true] {
        let replica = ReceivingReplica(fails: fails)
        let manager = TaskManager(replica: replica)
        let before = try await manager.changeVersion()
        let config = try SyncConfiguration(serverURL: "https://fixture.example.test", clientID: UUID(), encryptionSecret: "isolated-test")
        if fails {
            await #expect(throws: SynchronizationError.self) { try await manager.synchronize(using: config) }
        } else { _ = try await manager.synchronize(using: config) }
        let after = try await manager.changeVersion()
        #expect(after.tasks != before.tasks)
        #expect(after.taskOrigin == (fails ? .partialSynchronization : .synchronization))
        #expect((after.successfulSynchronization == nil) == fails)
        #expect(try await manager.tasks().first?.description == "Durably received")
    }
}

@Test func publicationFailureDoesNotTurnDurableSaveIntoRetryableCaptureFailure() async throws {
    let manager = TaskManager(replica: TestReplica(), changeTracking: UnavailableChangeStore())
    let saved = try await manager.create(TaskDraft(description: "Saved despite refresh failure"))
    #expect(try await manager.task(id: saved.id) == saved)
    await #expect(throws: TaskManagementError.self) { try await manager.changeVersion() }
}

private struct UnavailableChangeStore: TaskChangeTracking {
    func current() throws -> TaskChangeVersion { .initial }
    func record(_ domain: TaskChangeDomain, origin: TaskChangeOrigin) throws { throw TaskManagementError.storage("Refresh ledger unwritable") }
}

private actor ReceivingReplica: TaskSynchronizingReplica {
    let fails: Bool
    var records: [TaskRecord] = []
    init(fails: Bool) { self.fails = fails }
    func tasks() -> [TaskRecord] { records }
    func create(id: UUID, attributes: TaskAttributes) -> TaskRecord {
        let saved = TaskRecord(id: id, attributes: attributes)
        records.append(saved)
        return saved
    }
    func update(id: UUID, changes: TaskAttributePatch) throws -> TaskRecord { throw TaskManagementError.taskNotFound(id) }
    func synchronize(using configuration: SyncConfiguration) throws {
        records = [TaskRecord(id: UUID(), attributes: ["description": "Durably received", "status": "pending"])]
        if fails { throw SynchronizationError.failed("Response failed after durable receive") }
    }
}
