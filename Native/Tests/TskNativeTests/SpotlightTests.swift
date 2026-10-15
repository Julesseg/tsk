#if canImport(CoreSpotlight)
import Foundation
import Testing
import CoreSpotlight
import TskCore
import TskNative

@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_SPOTLIGHT_REAL_INDEX_TEST"] == "1")) @available(macOS 14.0, *)
func actualOwnedSpotlightIndexQueriesStableUUIDAndRemovesCompletedTasks() async throws {
    let token = UUID().uuidString
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(token)
    defer { try? FileManager.default.removeItem(at: directory) }
    let namespace = "tsk.fixture." + token
    let index = CoreSpotlightTaskIndex(namespace: namespace, indexName: namespace)
    let manager = TaskChampionSession.makeManager(directory: directory)
    do {
        let task = try await manager.create(TaskDraft(description: "Owned synthetic Spotlight " + token, attributes: ["opaque": "keep"]))
        #expect(try await manager.reconcileSpotlight(using: index) == 1)
        let found = try await eventuallyIndexed(index, count: 1)
        #expect(found.first?.identifier == namespace + "/task/" + task.id.uuidString.lowercased())
        #expect(found.first?.title == task.description)
        _ = try await manager.update(id: task.id, changes: ["description": "Changed synthetic " + token])
        _ = try await manager.reconcileSpotlight(using: index)
        let updated = try await eventuallyIndexed(index, count: 1, title: "Changed synthetic " + token)
        #expect(updated.first?.identifier == found.first?.identifier)
        _ = try await manager.complete(id: task.id)
        _ = try await manager.reconcileSpotlight(using: index)
        #expect(try await eventuallyIndexed(index, count: 0).isEmpty)
        #expect(try await manager.task(id: task.id).attributes["opaque"] == "keep")
        try await index.replace([])
    } catch { try? await index.replace([]); throw error }
}

@available(macOS 14.0, *)
private func eventuallyIndexed(_ index: CoreSpotlightTaskIndex, count: Int, title: String? = nil) async throws -> [SpotlightIndexedItem] {
    for _ in 0..<40 {
        let values = try await index.query()
        if values.count == count, title == nil || values.first?.title == title { return values }
        try await Task.sleep(for: .milliseconds(250))
    }
    let values = try await index.query()
    Issue.record("Actual Spotlight index did not converge to expected count/title; observed \(values)")
    return values
}

@Test @available(macOS 14.0, *)
func spotlightMissingCallbackDoesNotBlockDurableTaskAcknowledgement() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let index = ControlledSpotlightIndex()
    let effect = SpotlightTaskEffect(directory: directory, index: index, execution: .ownedWorker(SpotlightTaskEffect.containingAppOwner))
    let manager = TaskManager(replica: TaskChampionReplica(directory: directory), changeTracking: LocalTaskChangeStore(directory: directory), postCommitEffects: effect)
    let acknowledgement = SpotlightAcknowledgement()
    let creating = Task {
        let saved = try await manager.create(TaskDraft(description: "Durable before Spotlight callback", attributes: ["opaque": "preserve"]))
        await acknowledgement.receive(saved)
        return saved
    }
    await index.waitUntilBlocked()
    let deadline = Date().addingTimeInterval(5)
    while await acknowledgement.record == nil, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
    let acknowledged = await acknowledgement.record
    #expect(acknowledged != nil, "A durable save must be acknowledged while the optional Spotlight callback remains blocked")
    #expect(try await manager.tasks().first?.attributes["opaque"] == "preserve")
    await index.release()
    _ = try await creating.value
    _ = try await settledSpotlight(directory: directory)
}

private actor SpotlightAcknowledgement {
    var record: TaskRecord?
    func receive(_ value: TaskRecord) { record = value }
}

@Test @available(macOS 14.0, *)
func spotlightWorkerReadsLatestAcrossManagersAfterTaskAcknowledgement() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let index = ControlledSpotlightIndex()
    let effect = SpotlightTaskEffect(directory: directory, index: index, execution: .ownedWorker(SpotlightTaskEffect.containingAppOwner))
    let first = TaskManager(replica: TaskChampionReplica(directory: directory), changeTracking: LocalTaskChangeStore(directory: directory), postCommitEffects: effect)
    let second = TaskManager(replica: TaskChampionReplica(directory: directory), changeTracking: LocalTaskChangeStore(directory: directory), postCommitEffects: effect)
    let creatingFirst = Task { try await first.create(TaskDraft(description: "First durable task")) }
    await index.waitUntilBlocked()
    let creatingSecond = Task { try await second.create(TaskDraft(description: "Second durable task")) }
    let deadline = Date().addingTimeInterval(5)
    while try await second.tasks().count != 2, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
    #expect(try await second.tasks().count == 2, "The second durable write must not wait for the first OS index effect")
    await index.release()
    let a = try await creatingFirst.value, b = try await creatingSecond.value
    #expect(try await settledSpotlight(directory: directory).indexedCount == 2)
    #expect(Set(await index.items.map(\.taskID)) == Set([a.id, b.id]))
}

@Test @available(macOS 14.0, *)
func spotlightEffectFailureKeepsDurableSaveSuccessfulAndPersistsHonestRetryState() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let index = FailingNativeSpotlightIndex()
    let effect = SpotlightTaskEffect(directory: directory, index: index, execution: .ownedWorker(SpotlightTaskEffect.containingAppOwner))
    let manager = TaskManager(replica: TaskChampionReplica(directory: directory), changeTracking: LocalTaskChangeStore(directory: directory), postCommitEffects: effect)
    let task = try await manager.create(TaskDraft(description: "Saved while Spotlight fails", attributes: ["opaque": "keep"]))
    #expect(try await manager.task(id: task.id) == task)
    let failed = try await settledSpotlight(directory: directory, expectingError: true)
    #expect(failed.error != nil && failed.pending)
    await index.recover()
    let queued = await effect.reconcile(manager: manager)
    #expect(queued.pending)
    let recovered = try await settledSpotlight(directory: directory)
    #expect(recovered.indexedCount == 1 && recovered.error == nil)
}

@Test @available(macOS 14.0, *)
func blockedSpotlightCoalescesCrossManagerEditsAndCompletionsIntoLatestProjection() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let index = ControlledSpotlightIndex()
    let effect = SpotlightTaskEffect(directory: directory, index: index, execution: .ownedWorker(SpotlightTaskEffect.containingAppOwner))
    let first = TaskChampionSession.makeManager(directory: directory, postCommitEffects: effect)
    let second = TaskChampionSession.makeManager(directory: directory, postCommitEffects: effect)
    let a = try await first.create(TaskDraft(description: "Before held callback", attributes: ["opaque": "a"]))
    await index.waitUntilBlocked()
    let b = try await second.create(TaskDraft(description: "Second task", attributes: ["opaque": "b"]))
    _ = try await second.update(id: b.id, changes: ["description": "Newest projection", "project": "Work"])
    _ = try await first.complete(id: a.id)
    let pending = await effect.reconcile(manager: second)
    #expect(pending.pending)
    #expect(await index.callCount == 1)
    #expect(try await first.task(id: a.id).status == "completed")
    #expect(try await second.task(id: b.id).attributes["opaque"] == "b")
    await index.release()
    let settled = try await settledSpotlight(directory: directory)
    #expect(settled.indexedCount == 1 && !settled.pending)
    let items = await index.items
    #expect(items.count == 1 && items.first?.taskID == b.id)
    #expect(items.first?.title == "Newest projection" && items.first?.summary == "Work")
    #expect(await index.callCount == 2)
}

@Test @available(macOS 14.0, *)
func participantSpotlightRequestCannotConfirmContainingAppIndex() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let index = RecordingSpotlightIndex()
    let participant = SpotlightTaskEffect(directory: directory, index: index, execution: .participant)
    let manager = TaskChampionSession.makeManager(directory: directory, postCommitEffects: participant)
    let task = try await manager.create(TaskDraft(description: "Saved in ordinary extension"))
    #expect(try SpotlightTaskEffect.status(directory: directory).pending)
    #expect(await index.callCount == 0)
    let app = SpotlightTaskEffect(directory: directory, index: index, execution: .ownedWorker(SpotlightTaskEffect.containingAppOwner))
    _ = await app.reconcile(manager: manager)
    #expect(try await settledSpotlight(directory: directory).indexedCount == 1)
    #expect(await index.items.first?.taskID == task.id)
}

@Test @available(macOS 14.0, *)
func explicitSpotlightRepairReindexesAnUnchangedConfirmedRevision() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let index = RecordingSpotlightIndex()
    let effect = SpotlightTaskEffect(directory: directory, index: index, execution: .ownedWorker(SpotlightTaskEffect.containingAppOwner))
    let manager = TaskChampionSession.makeManager(directory: directory, postCommitEffects: effect)
    _ = try await manager.create(TaskDraft(description: "Repair without editing task"))
    _ = try await settledSpotlight(directory: directory)
    let before = try await manager.changeVersion()
    let pending = await effect.reconcile(manager: manager)
    #expect(pending.pending)
    _ = try await settledSpotlight(directory: directory)
    #expect(await index.callCount == 2)
    #expect(try await manager.changeVersion() == before)
}

@Test @available(macOS 14.0, *)
func spotlightPublicationAndMetadataFailuresPreserveSavedIdentityAndVisibleWarning() async throws {
    for brokenPublication in [true, false] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let index = RecordingSpotlightIndex()
        let effect = SpotlightTaskEffect(directory: directory, index: index, execution: .ownedWorker(SpotlightTaskEffect.containingAppOwner))
        let tracker: any TaskChangeTracking = brokenPublication ? FailingSpotlightChangePublication() : LocalTaskChangeStore(directory: directory)
        if !brokenPublication { try FileManager.default.createDirectory(at: directory.appendingPathComponent("spotlight-status.json"), withIntermediateDirectories: true) }
        let manager = TaskManager(replica: TaskChampionReplica(directory: directory), changeTracking: tracker, postCommitEffects: effect)
        let saved = try await manager.create(TaskDraft(description: "Saved despite integration metadata failure", attributes: ["opaque": "same identity"]))
        #expect(try await manager.task(id: saved.id) == saved)
        let status = try SpotlightTaskEffect.status(directory: directory)
        #expect(status.pending && status.error != nil)
        #expect(await index.callCount == 0)
    }
}

@Test @available(macOS 14.0, *)
func failedRevisionPublicationCannotBeClearedByAnOlderManagersRefresh() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let index = ControlledSpotlightIndex()
    let effect = SpotlightTaskEffect(directory: directory, index: index, execution: .ownedWorker(SpotlightTaskEffect.containingAppOwner))
    let app = TaskChampionSession.makeManager(directory: directory, postCommitEffects: effect)
    let first = try await app.create(TaskDraft(description: "Before publication failure"))
    await index.waitUntilBlocked()
    let failing = TaskManager(replica: TaskChampionReplica(directory: directory), changeTracking: FailingSpotlightChangePublication(), postCommitEffects: effect)
    let second = try await failing.create(TaskDraft(description: "Durable without revision publication"))
    #expect(try SpotlightTaskEffect.status(directory: directory).error != nil)
    _ = await effect.reconcile(manager: app, force: false)
    await index.release()
    let status = try await settledSpotlight(directory: directory)
    #expect(!status.pending)
    #expect(Set(await index.items.map(\.taskID)) == Set([first.id, second.id]), "An older manager must not certify a stale projection after clearing a failed publication warning")
}

private actor FailingSpotlightChangePublication: TaskChangeTracking {
    func current() -> TaskChangeVersion { .initial }
    func record(_ domain: TaskChangeDomain, origin: TaskChangeOrigin) throws { throw CocoaError(.fileWriteNoPermission) }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_NATIVE_PROBE_BINARY"] != nil)) @available(macOS 14.0, *)
func separateSpotlightProcessesKeepAcknowledgementsLiveAndRecoverLatestStateAfterOwnerDeath() throws {
    let environment = ProcessInfo.processInfo.environment
    let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/spotlight-liveness.py")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = [script.path, try #require(environment["TSK_NATIVE_PROBE_BINARY"]), try #require(environment["TSK_TASKCHAMPION_LIBRARY"])]
    let output = Pipe()
    process.standardOutput = output; process.standardError = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0, Comment(rawValue: String(decoding: data, as: UTF8.self)))
    if let path = environment["TSK_SPOTLIGHT_PROCESS_PROOF"] { try data.write(to: URL(fileURLWithPath: path)) }
}

private func settledSpotlight(directory: URL, expectingError: Bool = false) async throws -> TaskSpotlightIndexStatus {
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline {
        let status = try SpotlightTaskEffect.status(directory: directory)
        if expectingError ? status.error != nil : !status.pending { return status }
        try await Task.sleep(for: .milliseconds(10))
    }
    let status = try SpotlightTaskEffect.status(directory: directory)
    Issue.record("Spotlight worker did not reach the expected observed state: \(status)")
    return status
}

private actor ControlledSpotlightIndex: TaskSpotlightIndex {
    nonisolated let namespace = "owned.fixture.concurrent"
    var items: [TaskSpotlightItem] = []
    var callCount = 0
    private var first = true
    private var waiting: CheckedContinuation<Void, Never>?
    private var ready: CheckedContinuation<Void, Never>?
    func waitUntilBlocked() async { if waiting == nil { await withCheckedContinuation { ready = $0 } } }
    func release() { waiting?.resume(); waiting = nil }
    func replace(_ items: [TaskSpotlightItem]) async {
        callCount += 1
        if first {
            first = false
            await withCheckedContinuation { continuation in waiting = continuation; ready?.resume(); ready = nil }
        }
        self.items = items
    }
}
private actor FailingNativeSpotlightIndex: TaskSpotlightIndex {
    nonisolated let namespace = "owned.fixture.failure"
    var failing = true
    func recover() { failing = false }
    func replace(_ items: [TaskSpotlightItem]) throws { if failing { throw CocoaError(.fileWriteUnknown) } }
}
#endif

#if canImport(CoreSpotlight)
@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_SYNC_TEST_URL"] != nil && ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"] != nil)) @available(macOS 14.0, *)
func receivedEncryptedSyncCompletionAndDeletionReconcileSpotlightThroughCommonEffects() async throws {
    let environment = ProcessInfo.processInfo.environment
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let rawClient = try #require(environment["TSK_SYNC_TEST_CLIENT_ID"])
    let client = try #require(UUID(uuidString: rawClient))
    let configuration = try SyncConfiguration(serverURL: #require(environment["TSK_SYNC_TEST_URL"]), clientID: client, encryptionSecret: #require(environment["TSK_SYNC_TEST_SECRET"]))
    let directory = root.appendingPathComponent("phone"), index = ControlledSpotlightIndex()
    let phone = TaskChampionSession.makeManager(directory: directory, postCommitEffects: SpotlightTaskEffect(directory: directory, index: index, execution: .ownedWorker(SpotlightTaskEffect.containingAppOwner)))
    let completed = try await phone.create(TaskDraft(description: "Received completed task"))
    await index.waitUntilBlocked()
    let deleted = try await phone.create(TaskDraft(description: "Received deleted task", attributes: ["opaque": "keep"]))
    let initial = try await synchronizeWithBlockedSpotlight(phone, configuration: configuration, index: index, saved: completed)
    #expect(Set(initial.filter { $0.status == "pending" }.map(\.id)).isSuperset(of: [completed.id, deleted.id]))
    #expect(try SpotlightTaskEffect.status(directory: directory).pending)
    let taskrc = root.appendingPathComponent("taskrc"), desktop = root.appendingPathComponent("desktop")
    try """
    data.location=\(desktop.path)
    confirmation=no
    news.version=3.5.0
    journal.time=0
    uda.opaque.type=string
    sync.server.url=\(configuration.serverURL)
    sync.server.client_id=\(configuration.clientID.uuidString.lowercased())
    sync.encryption_secret=\(configuration.encryptionSecret)

    """.write(to: taskrc, atomically: true, encoding: .utf8)
    var proof: [[String: Any]] = []
    func task(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: try #require(environment["TSK_TASKWARRIOR_BINARY"]))
        process.arguments = ["rc:\(taskrc.path)", "rc.recurrence=off"] + arguments
        var isolated = environment; isolated["TASKRC"] = taskrc.path; isolated["TASKDATA"] = desktop.path
        process.environment = isolated
        let output = Pipe(), errors = Pipe(); process.standardOutput = output; process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile(), diagnostic = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        proof.append(["arguments": arguments, "exit": process.terminationStatus, "stdout": String(decoding: data, as: UTF8.self), "stderr": String(decoding: diagnostic, as: UTF8.self)])
        guard process.terminationStatus == 0 else { throw TaskManagementError.storage(String(decoding: diagnostic, as: UTF8.self)) }
    }
    defer { if let path = environment["TSK_SPOTLIGHT_TW_PROOF"], let data = try? JSONSerialization.data(withJSONObject: proof, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: URL(fileURLWithPath: path)) } }
    try task(["sync"])
    try task([completed.id.uuidString.lowercased(), "done"])
    try task([deleted.id.uuidString.lowercased(), "delete"])
    try task(["sync"])
    _ = try await synchronizeWithBlockedSpotlight(phone, configuration: configuration, index: index, saved: completed)
    #expect(await index.callCount == 1)
    #expect(try await phone.task(id: completed.id).status == "completed")
    await index.release()
    _ = try await settledSpotlight(directory: directory)
    #expect(!(await index.items.map(\.taskID)).contains(completed.id))
    #expect(!(await index.items.map(\.taskID)).contains(deleted.id))
    #expect(try await phone.task(id: completed.id).status == "completed")
    #expect(try await phone.task(id: deleted.id).attributes["opaque"] == "keep")
}
@available(macOS 14.0, *)
private func synchronizeWithBlockedSpotlight(_ manager: TaskManager, configuration: SyncConfiguration, index: ControlledSpotlightIndex, saved: TaskRecord) async throws -> [TaskRecord] {
    let acknowledged = SpotlightAcknowledgement()
    let synchronizing = Task {
        let records = try await manager.synchronize(using: configuration)
        await acknowledged.receive(saved)
        return records
    }
    let deadline = Date().addingTimeInterval(5)
    while await acknowledged.record == nil, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
    if await acknowledged.record == nil {
        Issue.record("Actual encrypted synchronization must return while Spotlight's independent callback is still held")
        await index.release()
    }
    return try await synchronizing.value
}

private actor RecordingSpotlightIndex: TaskSpotlightIndex {
    nonisolated let namespace = "owned.fixture.sync"
    var items: [TaskSpotlightItem] = []
    var callCount = 0
    func replace(_ items: [TaskSpotlightItem]) { callCount += 1; self.items = items }
}
#endif
