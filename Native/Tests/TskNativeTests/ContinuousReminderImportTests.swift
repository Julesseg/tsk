import Foundation
import Testing
import TskCore
import TskNative

@Test func continuousNativeMovesVerifyDurabilityBeforeSourceRemovalAndKeepOnlyDeviceConfiguration() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let device = UUID()
    let manager = TaskChampionSession.makeManager(directory: directory, reminderDeviceIdentifier: { device })
    let original = try await manager.create(TaskDraft(description: "Keep existing", attributes: ["opaque": "retained"]))
    try await manager.configureContinuousReminders(enabled: true, mappings: [ReminderListMapping(listID: "selected", project: "Moved")])
    let source = DurableMoveSource(directory: directory)
    let result = try #require(try await manager.runContinuousReminderImport(from: source))
    #expect(result.removedCount == 1)
    #expect(await source.sawDurableTask)
    #expect(await source.present == false)
    let reopened = TaskChampionSession.makeManager(directory: directory, reminderDeviceIdentifier: { device })
    #expect(try await reopened.continuousReminderStatus().active)
    #expect(try await reopened.tasks().count == 2)
    #expect(try await reopened.task(id: original.id) == original)
    let moved = try #require(result.imported.first)
    #expect(try await reopened.task(id: moved.id) == moved)
    #expect(moved.attributes.keys.sorted() == ["annotation_\(moved.attributes["entry"]!)", "description", "entry", "modified", "project", "status"])
    let otherDevice = UUID()
    let other = TaskChampionSession.makeManager(directory: directory, reminderDeviceIdentifier: { otherDevice })
    #expect(try await other.continuousReminderStatus().configuredOnAnotherDevice)
    #expect(try await other.runContinuousReminderImport(from: source) == nil)
    let file = directory.appendingPathComponent("continuous-reminders.json")
    let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    #expect(Set(json.keys) == ["enabled", "designatedDeviceID", "mappings"])
    #expect((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}

@Test func actualNativeDestinationFailureNeverInvokesSourceRemoval() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data("regular file blocks directory creation".utf8).write(to: directory)
    let manager = TaskChampionSession.makeManager(directory: directory)
    let source = DurableMoveSource(directory: directory)
    let result = try await manager.moveReminders(from: source, mappings: [ReminderListMapping(listID: "selected", project: "")])
    #expect(result.imported.isEmpty)
    #expect(result.removedCount == 0)
    #expect(result.failures.count == 1)
    #expect(await source.present)
    #expect(await source.sawDurableTask == false)
}

private actor DurableMoveSource: ReminderMoveSource {
    let directory: URL
    var present = true
    var sawDurableTask = false
    init(directory: URL) { self.directory = directory }
    func lists() async throws -> [ReminderList] { [ReminderList(id: "selected", title: "Work")] }
    func incompleteReminders(in listIDs: [String]) async throws -> [ReminderSnapshot] {
        present ? [ReminderSnapshot(listID: "selected", title: "Durable moved reminder", notes: "Keep source content")] : []
    }
    func moveCandidates(in listIDs: [String]) async throws -> [ReminderMoveCandidate] {
        try await incompleteReminders(in: listIDs).map { snapshot in ReminderMoveCandidate(snapshot: snapshot, removeSource: { try await self.remove() }) }
    }
    private func remove() async throws {
        let fresh = TaskChampionSession.makeManager(directory: directory)
        sawDurableTask = try await fresh.tasks().contains { $0.description == "Durable moved reminder" && $0.annotations.map(\.text) == ["Keep source content"] }
        guard sawDurableTask else { throw CocoaError(.fileReadCorruptFile) }
        present = false
    }
}
