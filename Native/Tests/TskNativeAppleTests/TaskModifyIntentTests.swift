#if canImport(AppIntents)
import AppIntents
import Foundation
import Testing
import TskCore
import TskNative

@available(macOS 13, iOS 16, *)
@Test func modifyIntentPersistsAllNamedInputsOfflineAndEmptyValuesPreserveThem() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = try await TaskChampionSession.open(directory: directory)
    let original = try await manager.create(TaskDraft(description: "Original", attributes: ["opaque": "keep", "café": "one", "cafe\u{301}": "two", "tag_café": "", "tag_cafe\u{301}": ""]))
    let entity = IntentTaskEntity(original)
    let scheduled = Date(timeIntervalSince1970: 1792224030)
    let deadline = Date(timeIntervalSince1970: 1792310430)
    let waiting = Date(timeIntervalSince1970: 1792137630)
    let result = try await ModifyTaskIntent(task: entity, description: "Revised", project: "Travel", tags: ["trip"], priority: .high, scheduled: scheduled, deadline: deadline, waitingUntil: waiting, directory: directory).perform()
    #expect(result.value?.id == original.id && result.value?.scheduled == scheduled && result.value?.deadline == deadline && result.value?.waitingUntil == waiting)
    let reopened = try await TaskChampionSession.open(directory: directory)
    let saved = try await reopened.task(id: original.id)
    #expect(saved.description == "Revised" && saved.project == "Travel" && saved.priority == "H")
    #expect(saved.tags.map { UTF8String($0) } == ["cafe\u{301}", "café", "trip"].map { UTF8String($0) })
    #expect(saved.attributes["opaque"] == "keep" && saved.attributes["café"] == "one" && saved.attributes["cafe\u{301}"] == "two")
    _ = try await ModifyTaskIntent(task: entity, description: "", project: "", tags: [], tagOperation: .replace, directory: directory).perform()
    #expect(try await reopened.task(id: original.id) == saved)
}
#endif

#if canImport(AppIntents)
@available(macOS 13, iOS 16, *)
@Test func modifyIntentTagModesClearsCompletedAndRejectedChangesSurviveReopening() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = try await TaskChampionSession.open(directory: directory)
    let original = try await manager.create(TaskDraft(description: "Modes", attributes: ["project": "Home", "priority": "M", "scheduled": "1792224030", "due": "1792310430", "wait": "1792137630", "tag_café": "", "tag_cafe\u{301}": "", "opaque": "retain"]))
    let entity = IntentTaskEntity(original)
    _ = try await ModifyTaskIntent(task: entity, tags: ["café"], tagOperation: .remove, directory: directory).perform()
    let reopened = try await TaskChampionSession.open(directory: directory)
    let removed = try await reopened.task(id: original.id)
    #expect(removed.attributes["tag_café"] == nil && removed.attributes["tag_cafe\u{301}"] != nil)
    _ = try await ModifyTaskIntent(task: entity, tags: ["rail"], tagOperation: .replace, directory: directory).perform()
    #expect(try await reopened.task(id: original.id).tags == ["rail"])
    let completed = try await manager.complete(id: original.id)
    _ = try await ModifyTaskIntent(task: entity, description: "Completed edit", tagOperation: .clear, clearProject: true, clearPriority: true, clearScheduled: true, clearDeadline: true, clearWaitingUntil: true, directory: directory).perform()
    let cleared = try await reopened.task(id: original.id)
    #expect(cleared.description == "Completed edit" && cleared.status == "completed" && cleared.attributes["end"] == completed.attributes["end"])
    #expect(cleared.project.isEmpty && cleared.priority.isEmpty && cleared.tags.isEmpty)
    #expect(cleared.plannedDate == nil && cleared.deadline == nil && cleared.waitUntil == nil && cleared.attributes["opaque"] == "retain")
    await #expect(throws: (any Error).self) { try await ModifyTaskIntent(task: entity, description: "Partial", project: "Travel", tags: ["bad tag"], directory: directory).perform() }
    await #expect(throws: (any Error).self) { try await ModifyTaskIntent(task: entity, description: "Partial", priority: .high, clearPriority: true, directory: directory).perform() }
    #expect(try await reopened.task(id: original.id) == cleared)
    let replica = TaskChampionReplica(directory: directory)
    let deleted = try await replica.create(id: UUID(), attributes: ["description": "Deleted", "status": "deleted"])
    await #expect(throws: (any Error).self) { try await ModifyTaskIntent(task: IntentTaskEntity(deleted), description: "No", directory: directory).perform() }
    let missingID = UUID()
    let missing = IntentTaskEntity(TaskRecord(id: missingID, attributes: [:]))
    await #expect(throws: TaskManagementError.taskNotFound(missingID)) { try await ModifyTaskIntent(task: missing, directory: directory).perform() }
    #expect(try await reopened.task(id: deleted.id) == deleted)
}
#endif
