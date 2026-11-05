import Foundation
import Testing
import TskCore
import TskNative

@Test func independentSharedParticipantsObserveLocalTaskAndViewCommits() async throws {
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
    let beforeMetadata = try await first.changeVersion()
    let view = try await second.saveView(name: "Shared custom", expression: "status:completed")
    let afterView = try await first.changeVersion()
    #expect(afterView.tasks == beforeMetadata.tasks)
    #expect(afterView.views != beforeMetadata.views)
    let reopened = TaskChampionSession.makeManager(directory: directory)
    #expect(try await reopened.changeVersion().schema == afterView.schema)
    #expect(try await reopened.savedViews() == [view])
    let saved = try await reopened.task(id: task.id)
    #expect(saved.attributes["foreign_é"] == "composed")
    #expect(saved.attributes["foreign_e\u{301}"] == "decomposed")
    let beforeFailure = try await reopened.changeVersion()
    await #expect(throws: TaskFilterError.self) { try await first.saveView(id: view.id, name: view.name, expression: "(") }
    #expect(try await reopened.changeVersion() == beforeFailure)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_NATIVE_PROBE_BINARY"] != nil))
func aSeparateProcessPublishesTaskAndViewVersionsToAnAlreadyOpenParticipant() async throws {
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
                if Date() < deadline, version.tasks != before.tasks && version.views != before.views { return version }
            }
            throw TaskManagementError.storage("Participant change stream ended before both commits")
        }
        group.addTask {
            try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
            throw TaskManagementError.storage("Participant commits were not observed within ten seconds")
        }
        defer { group.cancelAll() }
        return try #require(try await group.next())
    }
    #expect(after.tasks != before.tasks)
    #expect(after.views != before.views)
    #expect(after.schema == before.schema)
    #expect(after.taskOrigin == .local)
    let reread = try await manager.task(id: saved.id)
    #expect(reread.status == "completed")
    #expect(reread.attributes["opaque"] == "retain")
    let viewID = try #require(result["view"].flatMap(UUID.init(uuidString:)))
    #expect(try await manager.viewSnapshot(reference: .custom(viewID)).tasks.map(\.id) == [saved.id])
}



@Test func aCorruptSharedChangeLedgerAndInvalidSavedViewRemainVisibleErrors() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let app = TaskChampionSession.makeManager(directory: root)
    _ = try await app.create(TaskDraft(description: "Keep task after unavailable widget view"))
    let view = try await app.saveView(name: "Uses local schema", expression: "status:pending")
    let store = LocalTaskViewStore(directory: root)
    try await store.save([SavedTaskView(id: view.id, name: view.name, expression: "missingWidgetSchema:yes")])
    let participant = TaskChampionSession.makeManager(directory: root)
    await #expect(throws: TaskFilterError.self) { try await participant.viewSnapshot(reference: .custom(view.id)) }
    try Data("broken".utf8).write(to: root.appendingPathComponent("participant-changes.json"), options: .atomic)
    await #expect(throws: (any Error).self) { try await participant.changeVersion() }
    #expect(try await participant.tasks().count == 1)
}

@MainActor private func pumpWidgetProbeRunLoop() { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
