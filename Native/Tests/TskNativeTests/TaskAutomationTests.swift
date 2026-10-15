#if canImport(AppIntents)
import AppIntents
import Foundation
import Testing
import TskCore
import TskNative

@available(macOS 13, iOS 16, *)
@Test func completeAndRescheduleIntentsUsePersistentIdentityAndIndependentDateRoles() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let app = try await TaskChampionSession.open(directory: directory)
    let original = try await app.create(TaskDraft(description: "Native automation", attributes: ["scheduled": "1792051200", "due": "1792137600", "opaque": "retain", "start": "1792040000", "café": "composed", "cafe\u{301}": "decomposed"]))
    let entity = IntentTaskEntity(original)
    let planned = try await RescheduleTaskIntent(task: entity, role: .plannedDay, date: Date(timeIntervalSince1970: 1792224000), directory: directory).perform()
    #expect(planned.value?.id == original.id)
    let reopened = try await TaskChampionSession.open(directory: directory)
    let plannedRecord = try await reopened.task(id: original.id)
    #expect(plannedRecord.attributes["scheduled"] == "1792224000")
    #expect(plannedRecord.attributes["due"] == "1792137600")
    _ = try await RescheduleTaskIntent(task: entity, role: .deadline, date: Date(timeIntervalSince1970: 1792314000), directory: directory).perform()
    let completed = try await CompleteTaskIntent(task: entity, directory: directory).perform()
    #expect(completed.value?.id == original.id)
    let record = try await reopened.task(id: original.id)
    #expect(record.attributes["scheduled"] == "1792224000")
    #expect(record.attributes["due"] == "1792314000")
    #expect(record.status == "completed")
    #expect(record.attributes["start"] == nil)
    #expect(record.attributes["opaque"] == "retain")
    #expect(record.attributes["café"] == "composed")
    #expect(record.attributes["cafe\u{301}"] == "decomposed")
    _ = try await CompleteTaskIntent(task: entity, directory: directory).perform()
    #expect(try await reopened.task(id: original.id) == record)
}
#endif

#if canImport(AppIntents)
@available(macOS 13, iOS 16, *)
@Test func nativeAutomationReportsMissingAndRecurringTaskErrorsWithoutReplacingTheData() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let replica = TaskChampionReplica(directory: directory)
    let recurring = try await replica.create(id: UUID(), attributes: ["description": "Existing recurring template", "status": "recurring", "recur": "weekly", "opaque": "retain"])
    let entity = IntentTaskEntity(recurring)
    await #expect(throws: TaskManagementError.unsupportedTaskKind) { try await CompleteTaskIntent(task: entity, directory: directory).perform() }
    await #expect(throws: TaskManagementError.unsupportedTaskKind) { try await RescheduleTaskIntent(task: entity, role: .deadline, date: Date(), directory: directory).perform() }
    let missingID = UUID()
    let missing = IntentTaskEntity(TaskRecord(id: missingID, attributes: ["description": "Missing", "status": "pending"]))
    await #expect(throws: TaskManagementError.taskNotFound(missingID)) { try await CompleteTaskIntent(task: missing, directory: directory).perform() }
    #expect(try await replica.tasks() == [recurring])
}

@available(macOS 13, iOS 16, *)
@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_SYNC_TEST_URL"] != nil))
@MainActor func nativeAutomationCommitsWhileRealSynchronizationIsBlockedAndThenConverges() async throws {
    let environment = ProcessInfo.processInfo.environment
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let gate = root.appendingPathComponent("released")
    let proxy = Process()
    proxy.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/delayed-sync-proxy.py")
    let backend = try #require(environment["TSK_SYNC_TEST_URL"])
    proxy.arguments = [fixture.path, backend, root.path, "GET"]
    proxy.standardOutput = FileHandle.nullDevice
    proxy.standardError = FileHandle.nullDevice
    try proxy.run()
    defer { try? Data().write(to: gate); if proxy.isRunning { proxy.terminate() }; proxy.waitUntilExit() }
    try await automationWait { FileManager.default.fileExists(atPath: root.appendingPathComponent("url").path) }
    let url = try String(contentsOf: root.appendingPathComponent("url"), encoding: .utf8)
    let rawClient = try #require(environment["TSK_SYNC_TEST_CLIENT_ID"])
    let client = try #require(UUID(uuidString: rawClient))
    let secret = try #require(environment["TSK_SYNC_TEST_SECRET"])
    let direct = try SyncConfiguration(serverURL: backend, clientID: client, encryptionSecret: secret)
    let seed = TaskManager(replica: TaskChampionReplica(directory: root.appendingPathComponent("seed")))
    _ = try await seed.create(TaskDraft(description: "Remote version for blocked pull"))
    _ = try await seed.synchronize(using: direct)
    let configuration = try SyncConfiguration(serverURL: url, clientID: client, encryptionSecret: secret)
    let directory = root.appendingPathComponent("app")
    let app = TaskManager(replica: TaskChampionReplica(directory: directory))
    let original = try await app.create(TaskDraft(description: "Intent during real network barrier", attributes: ["due": "1792137600", "opaque": "retain"]))
    try await SyncConfigurationStore(directory: directory).save(configuration)
    let entity = IntentTaskEntity(original)
    _ = try await RescheduleTaskIntent(task: entity, role: .plannedDay, date: Date(timeIntervalSince1970: 1792224000), directory: directory).perform()
    try await automationWait { FileManager.default.fileExists(atPath: root.appendingPathComponent("blocked.json").path) }
    let safety = Task.detached { try await Task.sleep(for: .seconds(5)); try Data().write(to: gate) }
    defer { safety.cancel() }
    _ = try await RescheduleTaskIntent(task: entity, role: .deadline, date: Date(timeIntervalSince1970: 1792314000), directory: directory).perform()
    #expect(!FileManager.default.fileExists(atPath: gate.path), "Native rescheduling must acknowledge its local commit before releasing HTTP")
    _ = try await CompleteTaskIntent(task: entity, directory: directory).perform()
    #expect(!FileManager.default.fileExists(atPath: gate.path), "Native completion must acknowledge its local commit before releasing HTTP")
    try Data().write(to: gate)
    let peer = TaskManager(replica: TaskChampionReplica(directory: root.appendingPathComponent("peer")))
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while true {
        _ = try await peer.synchronize(using: direct)
        if let record = try await peer.tasks().first(where: { $0.id == original.id }), record.status == "completed" {
            #expect(record.attributes["scheduled"] == "1792224000")
            #expect(record.attributes["due"] == "1792314000")
            #expect(record.attributes["opaque"] == "retain")
            break
        }
        guard ContinuousClock.now < deadline else { throw TaskManagementError.storage("Native automation did not converge after barrier release") }
        try await Task.sleep(for: .milliseconds(50))
    }
}

@MainActor private func automationWait(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while !condition() {
        guard ContinuousClock.now < deadline else { throw TaskManagementError.storage("Native automation barrier timed out") }
        try await Task.sleep(for: .milliseconds(10))
    }
}
#endif

#if canImport(AppIntents)
@available(macOS 13, iOS 16, *)
@Test func nativeOccurrenceIntentsUseTheAtomicSharedCorePathAndPersistentAppDataset() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let replica = TaskChampionReplica(directory: directory)
    let parent = try await replica.create(id: UUID(), attributes: ["status": "recurring", "mask": "-", "opaque": "parent"])
    let child = try await replica.create(id: UUID(), attributes: ["status": "pending", "description": "Intent occurrence", "due": "2000000000", "parent": parent.id.uuidString, "imask": "0", "opaque": "child"])
    let entity = IntentTaskEntity(child)
    _ = try await RescheduleTaskIntent(task: entity, role: .deadline, date: Date(timeIntervalSince1970: 2000010000), directory: directory).perform()
    _ = try await CompleteTaskIntent(task: entity, directory: directory).perform()
    let app = try await TaskChampionSession.open(directory: directory)
    #expect(try await app.task(id: child.id).attributes["due"] == "2000010000")
    #expect(try await app.task(id: child.id).status == "completed")
    #expect(try await app.task(id: child.id).attributes["opaque"] == "child")
    #expect(try await app.task(id: parent.id).attributes["mask"] == "+")
}
#endif
