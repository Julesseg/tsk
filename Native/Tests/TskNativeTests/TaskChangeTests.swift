import Foundation
import Testing
import TskCore
import TskNative

@Test func independentSharedParticipantsObserveLocalTaskViewAndSchemaCommits() async throws {
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
    _ = try await first.saveAttributeDefinition(name: "score", type: .numeric)
    let reopened = TaskChampionSession.makeManager(directory: directory)
    #expect(try await reopened.changeVersion().schema != afterView.schema)
    #expect(try await reopened.savedViews() == [view])
    let saved = try await reopened.task(id: task.id)
    #expect(saved.attributes["foreign_é"] == "composed")
    #expect(saved.attributes["foreign_e\u{301}"] == "decomposed")
    let beforeFailure = try await reopened.changeVersion()
    await #expect(throws: TaskFilterError.self) { try await first.saveView(id: view.id, name: view.name, expression: "(") }
    #expect(try await reopened.changeVersion() == beforeFailure)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_NATIVE_PROBE_BINARY"] != nil))
func aSeparateProcessPublishesTaskAndDefinitionVersionsToAnAlreadyOpenParticipant() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let manager = TaskChampionSession.makeManager(directory: root)
    let saved = try await manager.create(TaskDraft(description: "Cross-process widget completion", attributes: ["opaque": "retain"]))
    let before = try await manager.changeVersion()
    var iterator = await manager.changeUpdates().makeAsyncIterator()
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
    let after = try #require(try await iterator.next())
    #expect(after.tasks != before.tasks)
    #expect(after.views != before.views)
    #expect(after.schema != before.schema)
    #expect(after.taskOrigin == .local)
    let reread = try await manager.task(id: saved.id)
    #expect(reread.status == "completed")
    #expect(reread.attributes["opaque"] == "retain")
    let viewID = try #require(result["view"].flatMap(UUID.init(uuidString:)))
    #expect(try await manager.viewSnapshot(reference: .custom(viewID)).tasks.map(\.id) == [saved.id])
    #expect(try await manager.attributeDefinitions().first?.name == UTF8String("processScore"))
}

#if canImport(AppIntents)
@Test func theWidgetCompletionIntentUsesTheSelectedRegisteredViewAndPublishesSharedChanges() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let app = TaskChampionSession.makeManager(directory: root)
    let saved = try await app.create(TaskDraft(description: "Widget actual AppIntent", attributes: ["opaque": "retain", "project": "Widget"]))
    let custom = try await app.saveView(name: "Widget pending", expression: "project:Widget status:pending")
    let selected = try TaskViewReference(id: TaskViewReference.custom(custom.id).id)
    let widget = try await TaskChampionSession.open(directory: root)
    #expect(try await widget.viewSnapshot(reference: selected).tasks.map(\.id) == [saved.id])
    let before = try await app.changeVersion()
    _ = try await CompleteTaskIntent(task: IntentTaskEntity(saved), directory: root).perform()
    #expect(try await app.changeVersion().tasks != before.tasks)
    #expect(try await widget.viewSnapshot(reference: selected).tasks.isEmpty)
    let completed = try await app.task(id: saved.id)
    #expect(completed.status == "completed")
    #expect(completed.attributes["opaque"] == "retain")
    try await app.deleteView(id: custom.id)
    await #expect(throws: TaskViewError.missingView(custom.id)) { try await widget.viewSnapshot(reference: selected) }
}
#endif

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
