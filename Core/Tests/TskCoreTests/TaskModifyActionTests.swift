import Foundation
import Testing
@testable import TskCore

@Test func modifyActionSavesNamedFieldsTogetherWithoutLosingIdentityOrOpaqueAttributes() async throws {
    let manager = TaskManager(replica: TestReplica())
    let original = try await manager.create(TaskDraft(description: "Original", attributes: ["project": "Home", "priority": "L", "due": "1792137600", "opaque": "retain", "café": "one", "cafe\u{301}": "two"]))
    let saved = try await manager.modifyTask(id: original.id, input: ModifyTaskInput(description: "  Revised  ", project: "Travel", tags: ["rail"], priority: "H", scheduled: Date(timeIntervalSince1970: 1792224030), waitingUntil: Date(timeIntervalSince1970: 1792220400)))
    #expect(saved.id == original.id && saved.description == "Revised")
    #expect(saved.project == "Travel" && saved.priority == "H" && saved.tags == ["rail"])
    #expect(saved.attributes["scheduled"] == "1792224030" && saved.attributes["due"] == "1792137600" && saved.attributes["wait"] == "1792220400")
    #expect(saved.attributes["opaque"] == "retain" && saved.attributes["café"] == "one" && saved.attributes["cafe\u{301}"] == "two")
    #expect(saved.attributes["entry"] == original.attributes["entry"])
}

@Test func modifyActionPreservesEmptyInputsAndUsesExplicitClearsForOptionalFields() async throws {
    let manager = TaskManager(replica: TestReplica())
    let original = try await manager.create(TaskDraft(description: "Keep", attributes: ["project": "Home", "priority": "M", "scheduled": "1792224030", "due": "1792310430", "wait": "1792137630", "tag_trip": ""]))
    let omitted = try await manager.modifyTask(id: original.id, input: ModifyTaskInput(description: "  ", project: "", tags: [], tagOperation: .replace, priority: ""))
    #expect(omitted == original)
    let cleared = try await manager.modifyTask(id: original.id, input: ModifyTaskInput(tagOperation: .clear, clearProject: true, clearPriority: true, clearScheduled: true, clearDeadline: true, clearWaitingUntil: true))
    #expect(cleared.description == "Keep" && cleared.tags.isEmpty)
    for key in ["project", "priority", "scheduled", "due", "wait", "tags", "tag_trip"] { #expect(cleared.attributes[key] == nil) }
}

@Test func modifyActionTagModesKeepByteExactIdentityAndValidateBeforeAnyChange() async throws {
    let manager = TaskManager(replica: TestReplica())
    let original = try await manager.create(TaskDraft(description: "Tags", attributes: ["tag_café": "", "tag_cafe\u{301}": "", "tag_keep": ""]))
    let added = try await manager.modifyTask(id: original.id, input: ModifyTaskInput(tags: ["new", "new"]))
    #expect(added.tags.map { UTF8String($0) } == ["cafe\u{301}", "café", "keep", "new"].map { UTF8String($0) })
    let removed = try await manager.modifyTask(id: original.id, input: ModifyTaskInput(tags: ["café"], tagOperation: .remove))
    #expect(removed.attributes["tag_café"] == nil && removed.attributes["tag_cafe\u{301}"] != nil)
    let replaced = try await manager.modifyTask(id: original.id, input: ModifyTaskInput(tags: ["rail"], tagOperation: .replace))
    #expect(replaced.tags == ["rail"] && replaced.attributes["tags"] == "rail")
    for input in [ModifyTaskInput(description: "Partial", tags: ["bad tag"]), ModifyTaskInput(project: "Travel", clearProject: true), ModifyTaskInput(priority: "H", clearPriority: true), ModifyTaskInput(scheduled: Date(), clearScheduled: true), ModifyTaskInput(deadline: Date(), clearDeadline: true), ModifyTaskInput(waitingUntil: Date(), clearWaitingUntil: true), ModifyTaskInput(tags: ["rail"], tagOperation: .clear), ModifyTaskInput(priority: "urgent"), ModifyTaskInput(scheduled: Date(timeIntervalSince1970: .infinity))] {
        await #expect(throws: (any Error).self) { try await manager.modifyTask(id: original.id, input: input) }
        #expect(try await manager.task(id: original.id) == replaced)
    }
}

@Test func modifyActionAllowsCompletedTasksRejectsUnavailableTargetsAndKeepsFailedSavesAtomic() async throws {
    let replica = TestReplica()
    let manager = TaskManager(replica: replica)
    let original = try await manager.create(TaskDraft(description: "Finished", attributes: ["opaque": "keep"]))
    let completed = try await manager.complete(id: original.id)
    let edited = try await manager.modifyTask(id: original.id, input: ModifyTaskInput(description: "Still editable"))
    #expect(edited.status == "completed" && edited.attributes["end"] == completed.attributes["end"])
    let deleted = try await replica.create(id: UUID(), attributes: ["description": "Deleted", "status": "deleted"])
    let recurring = try await replica.create(id: UUID(), attributes: ["description": "Template", "status": "recurring", "recur": "weekly"])
    await #expect(throws: TaskActionError.invalidInput("This task was deleted and cannot be modified.")) { try await manager.modifyTask(id: deleted.id, input: ModifyTaskInput()) }
    await #expect(throws: TaskManagementError.unsupportedTaskKind) { try await manager.modifyTask(id: recurring.id, input: ModifyTaskInput(description: "No")) }
    let missing = UUID()
    await #expect(throws: TaskManagementError.taskNotFound(missing)) { try await manager.modifyTask(id: missing, input: ModifyTaskInput()) }
    let failing = TaskManager(replica: ModifyUnwritableReplica(task: original))
    await #expect(throws: TaskManagementError.storage("Disk full")) { try await failing.modifyTask(id: original.id, input: ModifyTaskInput(description: "Partial", tags: ["new"], clearProject: true)) }
    #expect(try await failing.task(id: original.id) == original)
}

private struct ModifyUnwritableReplica: TaskReplica {
    let task: TaskRecord
    func tasks() async throws -> [TaskRecord] { [task] }
    func create(id: UUID, attributes: TaskAttributes) async throws -> TaskRecord { throw TaskManagementError.storage("Disk full") }
    func update(id: UUID, changes: TaskAttributePatch) async throws -> TaskRecord { throw TaskManagementError.storage("Disk full") }
}

@Test func modifyURLRequiresOneFullUUIDAndParsesNamedChangesAndExplicitClearControls() throws {
    let id = UUID()
    let action = try TaskActionURL(url: #require(URL(string: "tsk://modify?id=\(id.uuidString)&description=Revised&tags=rail&tag-operation=replace&scheduled=2026-11-05T08:30:00Z&clear-deadline=true&clear-project=false")))
    guard case .modify(let target, let input) = action else { Issue.record("Expected Modify"); return }
    #expect(target == id && input.description == "Revised" && input.tags == ["rail"] && input.tagOperation == .replace)
    #expect(input.scheduled == Date(timeIntervalSince1970: 1793867400) && input.clearDeadline && !input.clearProject)
    for query in ["", "id=1", "id=12345678", "id=\(id)&id=\(id)", "id=\(id)&filter=+work", "id=\(id)&priority=H&clear-priority=true", "id=\(id)&clear-scheduled=yes", "id=\(id)&scheduled=2026-11-05", "id=\(id)&tags=rail&tag-operation=clear", "id=\(id)&tag-operation=merge", "id=\(id)&recur=weekly"] {
        #expect(throws: (any Error).self) { try TaskActionURL(url: #require(URL(string: "tsk://modify?" + query))) }
    }
    #expect(throws: (any Error).self) { try TaskActionURL(url: #require(URL(string: "tsk://reschedule?id=\(id)"))) }
}
