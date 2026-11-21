import Foundation
import Testing
import TskCore
import TskNative

@Test func independentSharedParticipantsObserveLocalTaskCommits() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = TaskChampionSession.makeManager(directory: directory)
    let second = TaskChampionSession.makeManager(directory: directory)
    let initial = try await second.changeVersion()
    let task = try await first.create(TaskDraft(description: "Participant task", attributes: ["foreign_é": "composed", "foreign_e\u{301}": "decomposed"]))
    let created = try await second.changeVersion()
    #expect(created.tasks != initial.tasks)
    _ = try await second.complete(id: task.id)
    #expect(try await first.task(id: task.id).status == "completed")
    let reopened = TaskChampionSession.makeManager(directory: directory)
    let saved = try await reopened.task(id: task.id)
    #expect(saved.attributes["foreign_é"] == "composed")
    #expect(saved.attributes["foreign_e\u{301}"] == "decomposed")
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_NATIVE_PROBE_BINARY"] != nil))
func aSeparateProcessPublishesTaskVersionsToAnAlreadyOpenParticipant() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let manager = TaskChampionSession.makeManager(directory: root)
    let saved = try await manager.create(TaskDraft(description: "Cross-process widget completion", attributes: ["opaque": "retain"]))
    let before = try await manager.changeVersion()
    let updates = await manager.changeUpdates()
    var iterator = updates.makeAsyncIterator()
    #expect(try await iterator.next() == before)
    let binary = ProcessInfo.processInfo.environment["TSK_NATIVE_PROBE_BINARY"] ?? Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("tsk-native-probe").path
    let output = root.appendingPathComponent("process-result.json")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: binary)
    process.arguments = ["participant-change", root.path, saved.id.uuidString, output.path]
    try await MainActor.run { try process.run() }
    defer { if process.isRunning { process.terminate() } }
    let deadline = Date().addingTimeInterval(10)
    while process.isRunning && Date() < deadline {
        await pumpWidgetProbeRunLoop()
        try await Task.sleep(for: .milliseconds(20))
    }
    if process.isRunning { process.terminate() }
    #expect(!process.isRunning)
    let result = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String: String])
    #expect(result["error"] == nil)
    #expect(result["saved"] == saved.id.uuidString)
    let after = try await withThrowingTaskGroup(of: TaskChangeVersion.self) { group in
        group.addTask {
            for try await version in updates {
                if Date() < deadline, version.tasks != before.tasks { return version }
            }
            throw TaskManagementError.storage("Participant change stream ended before the task commit")
        }
        group.addTask {
            try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
            throw TaskManagementError.storage("Participant commits were not observed within ten seconds")
        }
        defer { group.cancelAll() }
        return try #require(try await group.next())
    }
    #expect(after.tasks != before.tasks)
    #expect(after.schema == before.schema)
    #expect(after.taskOrigin == .local)
    let reread = try await manager.task(id: saved.id)
    #expect(reread.status == "completed")
    #expect(reread.attributes["opaque"] == "retain")
}



@Test func aCorruptSharedChangeLedgerRemainsVisible() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let app = TaskChampionSession.makeManager(directory: root)
    _ = try await app.create(TaskDraft(description: "Keep task after unavailable widget view"))
    let participant = TaskChampionSession.makeManager(directory: root)
    try Data("broken".utf8).write(to: root.appendingPathComponent("participant-changes.json"), options: .atomic)
    await #expect(throws: (any Error).self) { try await participant.changeVersion() }
    #expect(try await participant.tasks().count == 1)
}

@MainActor private func pumpWidgetProbeRunLoop() { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
