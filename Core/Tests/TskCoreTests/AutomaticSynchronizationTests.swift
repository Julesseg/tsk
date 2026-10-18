import Foundation
import Testing
import TskCore

@Test func durableChangesCoalesceAndFinishDuringInFlightSynchronization() async throws {
    let replica = AutomaticSyncTestReplica()
    let manager = TaskManager(replica: replica)
    let configuration = try SyncConfiguration(serverURL: "https://tasks.example.test", clientID: UUID(), encryptionSecret: "isolated-secret")
    await manager.configureSynchronization(configuration)
    await manager.requestSynchronization(trigger: .appOpened)
    await replica.waitUntilStarted()
    let created = try await manager.create(TaskDraft(description: "Saved without waiting", attributes: ["opaque": "retain exactly"]))
    let edited = try await manager.update(id: created.id, changes: ["description": "Edited without waiting"])
    let completed = try await manager.complete(id: created.id)
    #expect(edited.description == "Edited without waiting")
    #expect(completed.status == "completed")
    #expect(completed.attributes["opaque"] == "retain exactly")
    let updates = await manager.synchronizationUpdates()
    await replica.release()
    for await state in updates {
        if case .synchronized = state { break }
        if case .failed(let error) = state { Issue.record("Synchronization failed: \(error)"); break }
    }
    #expect(await replica.syncCalls == 2)
    #expect(await replica.maximumConcurrentSyncs == 1)
    if case .synchronized = await manager.synchronizationStatus() {} else { Issue.record("Expected synchronized final state") }
}

private actor AutomaticSyncTestReplica: TaskSynchronizingReplica {
    var records: [UUID: TaskRecord] = [:]
    var writesFail = false
    func failWrites() { writesFail = true }
    var syncCalls = 0
    var activeSyncs = 0
    var maximumConcurrentSyncs = 0
    var startedWaiter: CheckedContinuation<Void, Never>?
    var releaseWaiter: CheckedContinuation<Void, Never>?
    func tasks() async throws -> [TaskRecord] { Array(records.values) }
    func create(id: UUID, attributes: TaskAttributes) async throws -> TaskRecord {
        if writesFail { throw TaskManagementError.storage("Injected commit failure") }
        let record = TaskRecord(id: id, attributes: attributes)
        records[id] = record
        return record
    }
    func update(id: UUID, changes: TaskAttributePatch) async throws -> TaskRecord {
        guard var record = records[id] else { throw TaskManagementError.taskNotFound(id) }
        for (key, value) in changes { record.attributes[key] = value }
        records[id] = record
        return record
    }
    func synchronize(using configuration: SyncConfiguration) async throws {
        syncCalls += 1
        activeSyncs += 1
        maximumConcurrentSyncs = max(maximumConcurrentSyncs, activeSyncs)
        defer { activeSyncs -= 1 }
        if syncCalls == 1 {
            startedWaiter?.resume()
            startedWaiter = nil
            await withCheckedContinuation { releaseWaiter = $0 }
        }
    }
    func waitUntilStarted() async {
        if syncCalls > 0 { return }
        await withCheckedContinuation { startedWaiter = $0 }
    }
    func release() { releaseWaiter?.resume(); releaseWaiter = nil }
}

@Test func failedLocalCommitNeverTriggersSynchronizationOrAcknowledgesTask() async throws {
    let replica = AutomaticSyncTestReplica()
    await replica.failWrites()
    let manager = TaskManager(replica: replica)
    let configuration = try SyncConfiguration(serverURL: "https://tasks.example.test", clientID: UUID(), encryptionSecret: "isolated-secret")
    await manager.configureSynchronization(configuration)
    await #expect(throws: TaskManagementError.storage("Injected commit failure")) {
        try await manager.create(TaskDraft(description: "Cannot acknowledge an uncommitted task"))
    }
    #expect(try await manager.tasks().isEmpty)
    #expect(await replica.syncCalls == 0)
    #expect(await manager.synchronizationStatus() == .ready)
}

@Test func annotationAddAndEditRequestSynchronizationOnlyAfterDurableCommit() async throws {
    let replica = AutomaticSyncTestReplica()
    let manager = TaskManager(replica: replica)
    let task = try await manager.create(TaskDraft(description: "Annotation sync"))
    let configuration = try SyncConfiguration(serverURL: "https://tasks.example.test", clientID: UUID(), encryptionSecret: "isolated-secret")
    await manager.configureSynchronization(configuration)
    let added = try await manager.addAnnotation(id: task.id, text: "Initial")
    await replica.waitUntilStarted()
    let reference = try #require(added.annotations.first?.reference.rawValue)
    _ = try await manager.editAnnotation(id: task.id, reference: reference, text: "Edited during synchronization")
    let updates = await manager.synchronizationUpdates()
    await replica.release()
    for await state in updates {
        if case .synchronized = state { break }
        if case .failed(let error) = state { Issue.record("Synchronization failed: \(error)"); break }
    }
    #expect(await replica.syncCalls == 2)
    #expect(try await manager.annotations(id: task.id).first?.text == "Edited during synchronization")
}
