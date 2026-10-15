import Foundation
import Testing
import TskCore
import TskNative

@Test func independentNativeManagersShareFailurePauseAndRestartRequiresExplicitRetry() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let device = UUID()
    let first = TaskChampionSession.makeManager(directory: directory, reminderDeviceIdentifier: { device })
    let second = TaskChampionSession.makeManager(directory: directory, reminderDeviceIdentifier: { device })
    try await first.configureContinuousReminders(enabled: true, mappings: [ReminderListMapping(listID: "work", project: "")])
    let source = NativeAdmissionSource(failRemoval: true)
    let result = try #require(try await first.runContinuousReminderImport(from: source))
    #expect(result.imported.count == 1)
    #expect(result.stopped)
    #expect(try await second.continuousReminderStatus().paused)
    #expect(try await second.runContinuousReminderImport(from: source) == nil)
    let reopened = TaskChampionSession.makeManager(directory: directory, reminderDeviceIdentifier: { device })
    #expect(try await reopened.continuousReminderStatus().paused)
    #expect(try await reopened.runContinuousReminderImport(from: source) == nil)
    #expect(try await reopened.tasks().count == 1)
    let retry = try #require(try await reopened.runContinuousReminderImport(from: source, retry: true))
    #expect(retry.imported.count == 1)
    #expect(try await reopened.tasks().count == 2)
}

actor NativeAdmissionSource: ReminderMoveSource {
    var present = true
    let failRemoval: Bool
    let gated: Bool
    var didHold = false
    var continuation: CheckedContinuation<Void, Never>?
    init(failRemoval: Bool = false, gated: Bool = false) { self.failRemoval = failRemoval; self.gated = gated }
    func lists() -> [ReminderList] { [ReminderList(id: "work", title: "Work")] }
    func incompleteReminders(in listIDs: [String]) -> [ReminderSnapshot] { present ? [ReminderSnapshot(listID: "work", title: "One shared source")] : [] }
    func moveCandidates(in listIDs: [String]) async -> [ReminderMoveCandidate] {
        let snapshots = incompleteReminders(in: listIDs)
        if gated && !didHold { didHold = true; await withCheckedContinuation { continuation = $0 } }
        return snapshots.map { ReminderMoveCandidate(snapshot: $0, removeSource: { try await self.remove() }) }
    }
    func waitForFetch() async throws {
        let deadline = Date().addingTimeInterval(10)
        while !didHold {
            guard Date() < deadline else { throw TaskManagementError.storage("Native reminder source did not reach its fetch") }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
    func releaseFetch() { continuation?.resume(); continuation = nil }
    func remove() throws {
        if failRemoval { throw TaskManagementError.storage("Actual adapter removal failure") }
        present = false
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_NATIVE_PROBE_BINARY"] != nil))
@MainActor func independentProcessesSerializeNormalMovesAndShareRemovalFailurePause() async throws {
    for failRemoval in [false, true] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = directory.appendingPathComponent("replica")
        let device = UUID()
        let manager = TaskChampionSession.makeManager(directory: storage, reminderDeviceIdentifier: { device })
        try await manager.configureContinuousReminders(enabled: true, mappings: [ReminderListMapping(listID: "work", project: "")])
        let source = directory.appendingPathComponent("owned-source")
        try Data("Owned fixture content".utf8).write(to: source)
        let release = directory.appendingPathComponent("release")
        let ready = [directory.appendingPathComponent("first-fetch"), directory.appendingPathComponent("second-fetch")]
        let outputs = [directory.appendingPathComponent("first-result"), directory.appendingPathComponent("second-result")]
        func launch(_ index: Int) throws -> Process {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["TSK_NATIVE_PROBE_BINARY"]))
            process.arguments = ["move-reminder", storage.path, source.path, ready[index].path, release.path, outputs[index].path, device.uuidString, failRemoval ? "fail" : "remove"]
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run()
            return process
        }
        let first = try launch(0)
        var processes = [first]
        defer {
            try? Data().write(to: release)
            for process in processes { if process.isRunning { process.terminate() }; process.waitUntilExit() }
        }
        try await waitForReminderProbe { FileManager.default.fileExists(atPath: ready[0].path) }
        let second = try launch(1); processes.append(second)
        try await waitForReminderProbe { FileManager.default.fileExists(atPath: ready[1].path + ".started") }
        let captured = try await manager.create(TaskDraft(description: "Ordinary capture during held process import"))
        #expect(try await manager.task(id: captured.id) == captured)
        try await Task.sleep(for: .milliseconds(150))
        #expect(!FileManager.default.fileExists(atPath: ready[1].path))
        try Data().write(to: release)
        try await waitForReminderProbe { outputs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) } }
        try await waitForReminderProbe { processes.allSatisfy { !$0.isRunning } }
        let result = try outputs.map { try #require(JSONSerialization.jsonObject(with: Data(contentsOf: $0)) as? [String: String]) }
        #expect(result[0]["saved"] == "1")
        #expect(result[1]["saved"] == "0")
        #expect(result.allSatisfy { $0["error"] == nil })
        #expect(try await manager.tasks().count == 2)
        #expect(FileManager.default.fileExists(atPath: source.path) == failRemoval)
        #expect(try await manager.continuousReminderStatus().paused == failRemoval)
        #expect(result[0]["removed"] == (failRemoval ? "0" : "1"))
    }
}

@MainActor private func waitForReminderProbe(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while !condition() {
        guard ContinuousClock.now < deadline else { throw TaskManagementError.storage("Reminder process probe timed out") }
        try await Task.sleep(for: .milliseconds(10))
    }
}

@Test func nativeCommitFailurePausesAnotherManagerAndConfigurationChangesResumeExplicitly() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let device = UUID()
    let first = TaskChampionSession.makeManager(directory: directory, reminderDeviceIdentifier: { device })
    let other = TaskChampionSession.makeManager(directory: directory, reminderDeviceIdentifier: { device })
    let original = try await first.create(TaskDraft(description: "Existing task", attributes: ["opaque": "keep"]))
    let mappings = [ReminderListMapping(listID: "work", project: "")]
    try await first.configureContinuousReminders(enabled: true, mappings: mappings)
    try reminderSQL(directory, "CREATE TRIGGER import_failure BEFORE INSERT ON operations BEGIN SELECT RAISE(ABORT, 'owned import save failure'); END;")
    let source = NativeAdmissionSource()
    let failure = try #require(try await first.runContinuousReminderImport(from: source))
    #expect(failure.imported.isEmpty)
    #expect(failure.stopped)
    #expect(await source.present)
    #expect(try await other.runContinuousReminderImport(from: source) == nil)
    #expect(try await other.continuousReminderStatus().paused)
    #expect(try await other.task(id: original.id) == original)
    let marker = directory.appendingPathComponent("continuous-reminders-paused")
    #expect(try Data(contentsOf: marker) == Data("paused".utf8))
    #expect((try FileManager.default.attributesOfItem(atPath: marker.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    try reminderSQL(directory, "DROP TRIGGER import_failure;")
    try await other.configureContinuousReminders(enabled: true, mappings: mappings)
    #expect(try await other.continuousReminderStatus().paused == false)
    #expect(try await other.runContinuousReminderImport(from: source)?.removedCount == 1)
    #expect(try await first.tasks().count == 2)
}

private func reminderSQL(_ directory: URL, _ statement: String) throws {
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    process.arguments = [directory.appendingPathComponent("taskchampion.sqlite3").path, statement]
    process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
    try process.run(); process.waitUntilExit()
    #expect(process.terminationStatus == 0)
}

@Test func nativeQueuedCancellationAndChangedSettingsNeverFetchOrDeleteStaleMappings() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let device = UUID()
    let first = TaskChampionSession.makeManager(directory: directory, reminderDeviceIdentifier: { device })
    let other = TaskChampionSession.makeManager(directory: directory, reminderDeviceIdentifier: { device })
    let mappings = [ReminderListMapping(listID: "work", project: "")]
    try await first.configureContinuousReminders(enabled: true, mappings: mappings)
    let source = NativeAdmissionSource(gated: true)
    let attempt = Task { try await first.runContinuousReminderImport(from: source) }
    try await source.waitForFetch()
    let canceled = Task { try await other.runContinuousReminderImport(from: source) }
    canceled.cancel()
    do { _ = try await canceled.value; Issue.record("Canceled queued scan must terminate") }
    catch is CancellationError {} catch { Issue.record("Unexpected error: \(error)") }
    let queued = Task { try await other.runContinuousReminderImport(from: source) }
    try await other.configureContinuousReminders(enabled: false, mappings: [])
    let capture = try await other.create(TaskDraft(description: "Capture while import fetch is held"))
    await source.releaseFetch()
    #expect(try await attempt.value?.stopped == true)
    #expect(try await queued.value == nil)
    #expect(await source.present)
    #expect(try await first.tasks() == [capture])
    try await other.configureContinuousReminders(enabled: true, mappings: mappings)
    #expect(try await other.runContinuousReminderImport(from: source)?.removedCount == 1)
}
