import Foundation
import Testing
import TskCore
import TskNative

@Test func sharedReceiptBaselineSurvivesReopenAndCorruptionNeverBecomesAnEmptySuccess() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let manager = TaskChampionSession.makeManager(directory: root)
    let saved = try await manager.create(TaskDraft(description: "Before first sync", attributes: ["due": "100", "foreign_é": "one", "foreign_e\u{301}": "two"]))
    let history = try await LocalTaskSynchronizationReceiptStore(directory: root).load()
    #expect(history?.baseline == [saved])
    #expect(history?.success == nil)
    let reopened = try await LocalTaskSynchronizationReceiptStore(directory: root).load()
    #expect(reopened?.baseline == [saved])
    try Data("broken".utf8).write(to: root.appendingPathComponent("synchronization-receipt.json"))
    await #expect(throws: (any Error).self) { try await LocalTaskSynchronizationReceiptStore(directory: root).load() }
    #expect(try await manager.task(id: saved.id) == saved)
    let effect = ReceiptNotificationEffect(center: ReceiptNotificationCenter(), directory: root)
    let participant = TaskChampionSession.makeManager(directory: root, postCommitEffects: effect)
    let edited = try await participant.update(id: saved.id, changes: ["description": "Durable despite corrupt receipt"])
    #expect(edited.description == "Durable despite corrupt receipt")
    #expect(edited.attributes["foreign_e\u{301}"] == "two")
    #expect(await effect.errors.count == 1)
    #expect(try String(contentsOf: root.appendingPathComponent("synchronization-receipt.json"), encoding: .utf8) == "broken")
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_SYNC_TEST_URL"] != nil))
func encryptedFinalReceiptSuppressesCompletedAndDeletedMissedEventsAndPersistsAcceptanceAcrossFreshFactories() async throws {
    let environment = ProcessInfo.processInfo.environment
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let rawClient = try #require(environment["TSK_SYNC_TEST_GENERATOR_31_CLIENT_ID"])
    let configuration = try SyncConfiguration(serverURL: #require(environment["TSK_SYNC_TEST_URL"]), clientID: #require(UUID(uuidString: rawClient)), encryptionSecret: #require(environment["TSK_SYNC_TEST_SECRET"]))
    let directory = root.appendingPathComponent("device")
    let center = ReceiptNotificationCenter()
    let effect = ReceiptNotificationEffect(center: center, directory: directory)
    let manager = TaskChampionSession.makeManager(directory: directory, now: { Date(timeIntervalSince1970: 2000) }, postCommitEffects: effect)
    let local = try await manager.create(TaskDraft(description: "Already known locally", attributes: ["due": "100", "foreign_é": "one", "foreign_e\u{301}": "two"]))
    let peer = TaskChampionReplica(directory: root.appendingPathComponent("encrypted-peer"))
    let missed = try await peer.create(id: UUID(), attributes: ["status": "pending", "description": "New missed", "scheduled": "200", "due": "200", "opaque": "retained"])
    let completed = try await peer.create(id: UUID(), attributes: ["status": "completed", "description": "Same successful snapshot completed", "due": "300"])
    let deleted = try await peer.create(id: UUID(), attributes: ["status": "deleted", "description": "Same successful snapshot deleted", "due": "400"])
    let future = try await peer.create(id: UUID(), attributes: ["status": "pending", "description": "Cancel after remote completion", "due": "4000000000"])
    try await peer.synchronize(using: configuration)
    _ = try await manager.synchronize(using: configuration)
    let first = try #require(try await LocalTaskSynchronizationReceiptStore(directory: directory).load()?.success)
    #expect(first.tasks.contains(missed))
    #expect(first.tasks.contains(completed))
    #expect(first.tasks.contains(deleted))
    #expect(await center.immediate.map(\.taskID) == [missed.id])
    #expect(await center.future.map(\.taskID) == [future.id])
    let reopened = TaskChampionSession.makeManager(directory: directory, now: { Date(timeIntervalSince1970: 2100) }, postCommitEffects: effect)
    _ = try await reopened.synchronize(using: configuration)
    let second = try #require(try await LocalTaskSynchronizationReceiptStore(directory: directory).load()?.success)
    #expect(second.id != first.id)
    #expect(await center.immediate.count == 1)
    let state = try await reopened.notificationState(using: LocalTaskNotificationStore(directory: directory))
    #expect(state.accepted.filter { $0.immediate == true }.map(\.event) == [TaskNotificationEvent(taskID: missed.id, source: .planned, storedSeconds: 200), TaskNotificationEvent(taskID: missed.id, source: .due, storedSeconds: 200)])
    #expect(try await reopened.task(id: local.id) == local)
    _ = try await peer.update(id: future.id, changes: ["status": "completed"])
    try await peer.synchronize(using: configuration)
    _ = try await reopened.synchronize(using: configuration)
    #expect(await center.future.isEmpty)
    #expect(await center.immediate.count == 1)
    let snapshot = try #require(try await LocalTaskSynchronizationReceiptStore(directory: directory).load()?.success)
    await reopened.configureSynchronization(nil)
    let newerLocal = try await reopened.create(TaskDraft(description: "After receipt", attributes: ["due": "500"]))
    let stable = try #require(try await LocalTaskSynchronizationReceiptStore(directory: directory).load()?.success)
    #expect(stable.id == snapshot.id)
    #expect(!stable.tasks.contains { $0.id == newerLocal.id })
    #expect(await effect.errors.isEmpty)
    if let path = environment["TSK_MISSED_NOTIFICATION_PROOF_PATH"] {
        let proof = ReceiptProof(first: first, final: stable, state: try await reopened.notificationState(using: LocalTaskNotificationStore(directory: directory)), submitted: await center.immediate)
        try JSONEncoder().encode(proof).write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}

private struct ReceiptProof: Encodable {
    let first: TaskSynchronizationReceipt
    let final: TaskSynchronizationReceipt
    let state: TaskNotificationState
    let submitted: [TaskNotificationRequest]
}
private actor ReceiptNotificationEffect: TaskPostCommitEffect {
    let center: ReceiptNotificationCenter
    let directory: URL
    var errors: [String] = []
    init(center: ReceiptNotificationCenter, directory: URL) { self.center = center; self.directory = directory }
    func apply(to manager: TaskManager, origin: TaskChangeOrigin) async { await apply(to: manager, origin: origin, locallyWritten: []) }
    func apply(to manager: TaskManager, origin: TaskChangeOrigin, locallyWritten: [TaskRecord]) async {
        do { _ = try await manager.reconcileNotifications(center: center, store: LocalTaskNotificationStore(directory: directory), locallyWritten: locallyWritten) }
        catch { errors.append(error.localizedDescription) }
    }
}
private actor ReceiptNotificationCenter: TaskNotificationCenter {
    var immediate: [TaskNotificationRequest] = []
    var future: [TaskNotificationRequest] = []
    func authorization() -> TaskNotificationAuthorization { .authorized }
    func requestAuthorization() -> TaskNotificationAuthorization { .authorized }
    func pending() -> [PendingTaskNotification] { future.map { PendingTaskNotification(identifier: $0.identifier, request: $0, nextTriggerDate: $0.fireDate) } }
    func add(_ request: TaskNotificationRequest) { future.removeAll { $0.identifier == request.identifier }; future.append(request) }
    func addImmediate(_ request: TaskNotificationRequest) { immediate.append(request) }
    func remove(identifiers: [String]) { future.removeAll { identifiers.contains($0.identifier) } }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_SYNC_TEST_URL"] != nil))
@MainActor func firstPartialSyncCannotBecomeTheBaselineAndOnlyAFinalSuccessCanMakeItEligible() async throws {
    let env = ProcessInfo.processInfo.environment
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let backend = try #require(env["TSK_SYNC_TEST_URL"])
    let proxy = Process()
    proxy.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    proxy.arguments = [URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/delayed-sync-proxy.py").path, backend, root.path, "POST"]
    proxy.standardOutput = FileHandle.nullDevice; proxy.standardError = FileHandle.nullDevice
    try proxy.run()
    defer { try? Data().write(to: root.appendingPathComponent("released")); if proxy.isRunning { proxy.terminate() }; proxy.waitUntilExit() }
    try await waitForReceiptFile(root.appendingPathComponent("url"))
    let proxyURL = try String(contentsOf: root.appendingPathComponent("url"), encoding: .utf8)
    try await exerciseFirstPartialReceipt(root: root, backend: backend, proxyURL: proxyURL)
}

private func exerciseFirstPartialReceipt(root: URL, backend: String, proxyURL: String) async throws {
    let env = ProcessInfo.processInfo.environment
    let rawClient = try #require(env["TSK_SYNC_TEST_GENERATOR_131_CLIENT_ID"])
    let client = try #require(UUID(uuidString: rawClient))
    let secret = try #require(env["TSK_SYNC_TEST_SECRET"])
    let direct = try SyncConfiguration(serverURL: backend, clientID: client, encryptionSecret: secret)
    let peer = TaskChampionReplica(directory: root.appendingPathComponent("peer"))
    let remote = try await peer.create(id: UUID(), attributes: ["status": "pending", "description": "Partial learned before first success", "due": "200"])
    try await peer.synchronize(using: direct)
    let directory = root.appendingPathComponent("device")
    let replica = TaskChampionReplica(directory: directory)
    _ = try await replica.create(id: UUID(), attributes: ["status": "pending", "description": "Forces accepted POST"])
    let blocked = try SyncConfiguration(serverURL: proxyURL, clientID: client, encryptionSecret: secret)
    let synchronization = Task { try await replica.synchronize(using: blocked) }
    try await waitForReceiptFile(root.appendingPathComponent("blocked.json"))
    let history = try #require(try await LocalTaskSynchronizationReceiptStore(directory: directory).load())
    synchronization.cancel()
    _ = await synchronization.result
    #expect(history.success == nil)
    #expect(!history.baseline.contains { $0.id == remote.id })
    #expect(!(try await replica.tasks()).contains { $0.id == remote.id })
    try Data().write(to: root.appendingPathComponent("released"))
    let blockedReceipt = directory.appendingPathComponent("synchronization-receipt.pending")
    try FileManager.default.createDirectory(at: blockedReceipt, withIntermediateDirectories: true)
    await #expect(throws: (any Error).self) { try await replica.synchronize(using: direct) }
    #expect(try await replica.tasks().contains { $0.id == remote.id })
    #expect(try await LocalTaskSynchronizationReceiptStore(directory: directory).load()?.success == nil)
    let manager = TaskChampionSession.makeManager(directory: directory, now: { Date(timeIntervalSince1970: 1000) })
    let state = LocalTaskNotificationStore(directory: directory), center = ReceiptNotificationCenter()
    _ = try await manager.reconcileNotifications(center: center, store: state)
    #expect(await center.immediate.isEmpty)
    #expect(!(try await manager.notificationState(using: state)).known.contains { $0.taskID == remote.id })
    try FileManager.default.removeItem(at: blockedReceipt)
    try await replica.synchronize(using: direct)
    _ = try await manager.reconcileNotifications(center: center, store: state)
    #expect(await center.immediate.map(\.taskID) == [remote.id])
}

private func waitForReceiptFile(_ path: URL) async throws {
    let limit = ContinuousClock.now.advanced(by: .seconds(15))
    while !FileManager.default.fileExists(atPath: path.path) {
        guard ContinuousClock.now < limit else { throw TaskManagementError.storage("Receipt fixture timed out waiting for " + path.lastPathComponent) }
        try await Task.sleep(for: .milliseconds(10))
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_SYNC_TEST_URL"] != nil && ProcessInfo.processInfo.environment["TSK_NATIVE_PROBE_BINARY"] != nil))
@MainActor func independentProcessesShareTheAcceptedMissedLedgerInsteadOfResubmittingTheSameReceipt() async throws {
    let env = ProcessInfo.processInfo.environment
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let rawClient = try #require(env["TSK_SYNC_TEST_GENERATOR_231_CLIENT_ID"])
    let configuration = try SyncConfiguration(serverURL: #require(env["TSK_SYNC_TEST_URL"]), clientID: #require(UUID(uuidString: rawClient)), encryptionSecret: #require(env["TSK_SYNC_TEST_SECRET"]))
    let peer = TaskChampionReplica(directory: root.appendingPathComponent("peer"))
    let remote = try await peer.create(id: UUID(), attributes: ["status": "pending", "description": "Cross process missed", "due": "200"])
    try await peer.synchronize(using: configuration)
    let directory = root.appendingPathComponent("device")
    try await TaskChampionReplica(directory: directory).synchronize(using: configuration)
    let output = root.appendingPathComponent("submissions.jsonl")
    try Data().write(to: output)
    let binary = try #require(env["TSK_NATIVE_PROBE_BINARY"])
    var processes: [Process] = []
    for index in 0..<2 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["reconcile-notifications", directory.path, output.path, root.appendingPathComponent("result-\(index).json").path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); processes.append(process)
    }
    defer { for process in processes { if process.isRunning { process.terminate() }; process.waitUntilExit() } }
    for index in 0..<2 {
        try await waitForReceiptFile(root.appendingPathComponent("result-\(index).json"))
        let result = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: root.appendingPathComponent("result-\(index).json")))
        #expect(result["result"] == "reconciled")
    }
    let submitted = try String(contentsOf: output, encoding: .utf8).split(separator: "\n").map { try JSONDecoder().decode(TaskNotificationRequest.self, from: Data($0.utf8)) }
    #expect(submitted.map(\.taskID) == [remote.id])
    let state = try await TaskChampionSession.makeManager(directory: directory).notificationState(using: LocalTaskNotificationStore(directory: directory))
    #expect(state.accepted.filter { $0.immediate == true }.map(\.event) == [TaskNotificationEvent(taskID: remote.id, source: .due, storedSeconds: 200)])
}
