import Foundation
import Testing
import TskCore
import TskNative

@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_SYNC_TEST_URL"] != nil))
func durableNativeMutationsFinishWhileRealServerResponsesRemainBlocked() async throws {
    for blockedMethod in ["GET", "POST"] {
        try await exerciseBlockedServerResponse(method: blockedMethod)
    }
}

private func exerciseBlockedServerResponse(method: String) async throws {
    let environment = ProcessInfo.processInfo.environment
    let backend = try #require(environment["TSK_SYNC_TEST_URL"])
    let secret = try #require(environment["TSK_SYNC_TEST_SECRET"])
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let gate = directory.appendingPathComponent("released")
    let proxy = Process()
    proxy.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/delayed-sync-proxy.py")
    proxy.arguments = [fixture.path, backend, directory.path, method]
    proxy.standardOutput = FileHandle.nullDevice
    proxy.standardError = FileHandle.nullDevice
    try proxy.run()
    defer {
        try? Data().write(to: gate)
        if proxy.isRunning { proxy.terminate() }
        proxy.waitUntilExit()
    }
    try await waitForFile(directory.appendingPathComponent("url"))
    let proxyURL = try String(contentsOf: directory.appendingPathComponent("url"), encoding: .utf8)
    let rawClientID = try #require(environment["TSK_SYNC_TEST_CLIENT_ID"])
    let clientID = try #require(UUID(uuidString: rawClientID))
    let configuration = try SyncConfiguration(serverURL: proxyURL, clientID: clientID, encryptionSecret: secret)
    let manager = TaskManager(replica: TaskChampionReplica(directory: directory.appendingPathComponent("native")))
    let original = try await manager.create(TaskDraft(description: "Before blocked \(method)", attributes: ["opaque": "retain original"]))
    let attempt = Task { try await manager.synchronize(using: configuration) }
    let deadline = Task.detached {
        try await Task.sleep(for: .seconds(5))
        try Data().write(to: gate)
    }
    defer { deadline.cancel() }
    try await waitForFile(directory.appendingPathComponent("blocked.json"))
    let blocked = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("blocked.json"))) as? [String: Any])
    #expect(blocked["method"] as? String == method)
    if method == "POST" { #expect(blocked["status"] as? Int == 200) }
    let created = try await manager.create(TaskDraft(description: "Captured during blocked \(method)", attributes: ["opaque": "retain in-flight"]))
    let capturedWhileBlocked = !FileManager.default.fileExists(atPath: gate.path)
    #expect(capturedWhileBlocked, "Durable capture must finish before the held server response is released")
    let edited = try await manager.update(id: created.id, changes: ["description": "Edited during blocked \(method)"])
    let editedWhileBlocked = !FileManager.default.fileExists(atPath: gate.path)
    #expect(editedWhileBlocked, "Durable edit must finish before the held server response is released")
    let completed = try await manager.complete(id: created.id)
    let completedWhileBlocked = !FileManager.default.fileExists(atPath: gate.path)
    #expect(completedWhileBlocked, "Durable completion must finish before the held server response is released")
    #expect(edited.attributes["opaque"] == "retain in-flight")
    #expect(completed.status == "completed")
    #expect(completed.attributes["opaque"] == "retain in-flight")
    try Data().write(to: gate)
    _ = try await attempt.value
    _ = try await manager.synchronize(using: configuration)
    let direct = try SyncConfiguration(serverURL: backend, clientID: clientID, encryptionSecret: secret)
    let received = TaskManager(replica: TaskChampionReplica(directory: directory.appendingPathComponent("received")))
    let final = try await received.synchronize(using: direct)
    #expect(final.filter { $0.id == original.id }.count == 1)
    #expect(final.filter { $0.id == created.id }.count == 1)
    #expect(try await received.task(id: original.id).attributes["opaque"] == "retain original")
    #expect(try await received.task(id: created.id) == completed)
}

private func waitForFile(_ file: URL) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while !FileManager.default.fileExists(atPath: file.path) {
        guard ContinuousClock.now < deadline else { throw SynchronizationError.failed("Isolated server barrier did not arrive") }
        try await Task.sleep(for: .milliseconds(10))
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_SYNC_TEST_URL"] != nil))
func automaticSynchronizationRecoversAfterRealServerFailureAndConnectivitySignal() async throws {
    let environment = ProcessInfo.processInfo.environment
    let backend = try #require(environment["TSK_SYNC_TEST_URL"])
    let secret = try #require(environment["TSK_SYNC_TEST_SECRET"])
    let rawClientID = try #require(environment["TSK_SYNC_TEST_CLIENT_ID"])
    let clientID = try #require(UUID(uuidString: rawClientID))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let proxy = Process()
    proxy.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/delayed-sync-proxy.py")
    proxy.arguments = [fixture.path, backend, directory.path, "FAIL"]
    proxy.standardOutput = FileHandle.nullDevice
    proxy.standardError = FileHandle.nullDevice
    try proxy.run()
    defer { if proxy.isRunning { proxy.terminate() }; proxy.waitUntilExit() }
    try await waitForFile(directory.appendingPathComponent("url"))
    let proxyURL = try String(contentsOf: directory.appendingPathComponent("url"), encoding: .utf8)
    let configuration = try SyncConfiguration(serverURL: proxyURL, clientID: clientID, encryptionSecret: secret)
    let manager = TaskManager(replica: TaskChampionReplica(directory: directory.appendingPathComponent("native")))
    await manager.configureSynchronization(configuration)
    let updates = await manager.synchronizationUpdates()
    await manager.requestSynchronization(trigger: .appOpened)
    for await state in updates { if case .failed = state { break } }
    let local = try await manager.create(TaskDraft(description: "Saved during real server outage", attributes: ["opaque": "retain through recovery"]))
    #expect(try await manager.task(id: local.id) == local)
    try Data().write(to: directory.appendingPathComponent("online"))
    await manager.requestSynchronization(trigger: .connectivityRestored)
    for await state in updates { if case .synchronized = state { break } }
    let direct = try SyncConfiguration(serverURL: backend, clientID: clientID, encryptionSecret: secret)
    let received = TaskManager(replica: TaskChampionReplica(directory: directory.appendingPathComponent("received")))
    _ = try await received.synchronize(using: direct)
    #expect(try await received.task(id: local.id) == local)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_SYNC_TEST_URL"] != nil))
func reopenedNativeSessionLoadsConfigurationAndUsesCommonAutomaticPolicy() async throws {
    let environment = ProcessInfo.processInfo.environment
    let url = try #require(environment["TSK_SYNC_TEST_URL"])
    let secret = try #require(environment["TSK_SYNC_TEST_SECRET"])
    let rawClientID = try #require(environment["TSK_SYNC_TEST_CLIENT_ID"])
    let clientID = try #require(UUID(uuidString: rawClientID))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let configuration = try SyncConfiguration(serverURL: url, clientID: clientID, encryptionSecret: secret)
    try await SyncConfigurationStore(directory: directory).save(configuration)
    let reopened = try await TaskChampionSession.open(directory: directory)
    let updates = await reopened.synchronizationUpdates()
    let captured = try await reopened.create(TaskDraft(description: "Common native session policy", attributes: ["opaque": "retain reopened session"]))
    for await state in updates {
        if case .synchronized = state { break }
        if case .failed(let error) = state { Issue.record("Unexpected failure: \(error)"); break }
    }
    let received = TaskManager(replica: TaskChampionReplica(directory: directory.appendingPathComponent("received")))
    _ = try await received.synchronize(using: configuration)
    #expect(try await received.task(id: captured.id) == captured)
}
