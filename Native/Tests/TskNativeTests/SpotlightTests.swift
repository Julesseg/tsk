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
func spotlightEffectsAwaitIndexingAfterReleasingMutationLeaseAndReadLatestAcrossManagers() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let index = ControlledSpotlightIndex()
    let effect = SpotlightTaskEffect(directory: directory, index: index)
    let first = TaskManager(replica: TaskChampionReplica(directory: directory), postCommitEffects: effect)
    let second = TaskManager(replica: TaskChampionReplica(directory: directory), postCommitEffects: effect)
    let creatingFirst = Task { try await first.create(TaskDraft(description: "First durable task")) }
    await index.waitUntilBlocked()
    let creatingSecond = Task { try await second.create(TaskDraft(description: "Second durable task")) }
    let deadline = Date().addingTimeInterval(5)
    while try await second.tasks().count != 2, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
    #expect(try await second.tasks().count == 2, "The second durable write must not wait for the first OS index effect")
    await index.release()
    let a = try await creatingFirst.value, b = try await creatingSecond.value
    #expect(Set(await index.items.map(\.taskID)) == Set([a.id, b.id]))
    #expect(try SpotlightTaskEffect.status(directory: directory).indexedCount == 2)
}

@Test @available(macOS 14.0, *)
func spotlightEffectFailureKeepsDurableSaveSuccessfulAndPersistsHonestRetryState() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let index = FailingNativeSpotlightIndex()
    let effect = SpotlightTaskEffect(directory: directory, index: index)
    let manager = TaskManager(replica: TaskChampionReplica(directory: directory), postCommitEffects: effect)
    let task = try await manager.create(TaskDraft(description: "Saved while Spotlight fails", attributes: ["opaque": "keep"]))
    #expect(try await manager.task(id: task.id) == task)
    #expect(try SpotlightTaskEffect.status(directory: directory).error != nil)
    await index.recover()
    let recovered = await effect.reconcile(manager: manager)
    #expect(recovered.indexedCount == 1 && recovered.error == nil)
}

private actor ControlledSpotlightIndex: TaskSpotlightIndex {
    nonisolated let namespace = "owned.fixture.concurrent"
    var items: [TaskSpotlightItem] = []
    private var first = true
    private var waiting: CheckedContinuation<Void, Never>?
    private var ready: CheckedContinuation<Void, Never>?
    func waitUntilBlocked() async { if waiting == nil { await withCheckedContinuation { ready = $0 } } }
    func release() { waiting?.resume(); waiting = nil }
    func replace(_ items: [TaskSpotlightItem]) async {
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
    let directory = root.appendingPathComponent("phone"), index = RecordingSpotlightIndex()
    let phone = TaskManager(replica: TaskChampionReplica(directory: directory), postCommitEffects: SpotlightTaskEffect(directory: directory, index: index))
    let completed = try await phone.create(TaskDraft(description: "Received completed task"))
    let deleted = try await phone.create(TaskDraft(description: "Received deleted task", attributes: ["opaque": "keep"]))
    _ = try await phone.synchronize(using: configuration)
    #expect(Set(await index.items.map(\.taskID)).isSuperset(of: [completed.id, deleted.id]))
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
    _ = try await phone.synchronize(using: configuration)
    #expect(!(await index.items.map(\.taskID)).contains(completed.id))
    #expect(!(await index.items.map(\.taskID)).contains(deleted.id))
    #expect(try await phone.task(id: completed.id).status == "completed")
    #expect(try await phone.task(id: deleted.id).attributes["opaque"] == "keep")
}
private actor RecordingSpotlightIndex: TaskSpotlightIndex {
    nonisolated let namespace = "owned.fixture.sync"
    var items: [TaskSpotlightItem] = []
    func replace(_ items: [TaskSpotlightItem]) { self.items = items }
}
#endif
