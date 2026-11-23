import Foundation
import Testing
@testable import TskCore

@Test func selectionOrganizationChangesOnlyStagedFieldsAndPreservesMembership() async throws {
    let first = TaskRecord(id: UUID(), attributes: ["description": "First", "status": "pending", "project": "Home", "priority": "H", "tag_home": "opaque", "tags": "home"])
    let second = TaskRecord(id: UUID(), attributes: ["description": "Second", "status": "pending", "project": "Work", "tag_work": "", "tags": "work", "future": "retain"])
    let replica = OccurrenceReplica(records: [first, second])
    let manager = TaskManager(replica: replica)
    let ids = [first.id, second.id, first.id]
    var changes = TaskSelectionChanges()
    changes.tag = .add("home")
    #expect(try changes.modifies(tasks: [first, second]))
    #expect(try !changes.modifies(tasks: [first]))
    _ = try await manager.applySelection(ids: ids, changes: changes)
    #expect(try await manager.task(id: first.id) == first)
    let tagged = try await manager.task(id: second.id)
    #expect(tagged.tags == ["home", "work"] && tagged.attributes["tags"] == "home,work")
    #expect(tagged.project == "Work" && tagged.priority == "" && tagged.attributes["future"] == "retain")
    changes.tag = .remove("home")
    changes.project = ""
    changes.priority = ""
    _ = try await manager.applySelection(ids: ids, changes: changes)
    #expect(try await manager.tasks(project: .project("Home")).isEmpty)
    #expect(try await manager.tasks(filter: "+home").isEmpty)
    let remaining = try await manager.tasks(filter: "+work")
    #expect(remaining.map(\.id) == [second.id])
    #expect(remaining.first?.attributes["tags"] == "work")
    #expect(try await manager.task(id: first.id).attributes["priority"] == nil)
    #expect(try await manager.task(id: second.id).attributes["project"] == nil)
    #expect(await replica.batches == 2)
}

@Test func selectionClearRemovesEmptyImportedFieldsAndProtectsUnknownTagKeys() async throws {
    let original = TaskRecord(id: UUID(), attributes: ["status": "pending", "project": "", "priority": "", "tag_": "unknown"])
    let replica = OccurrenceReplica(records: [original])
    let manager = TaskManager(replica: replica)
    var changes = TaskSelectionChanges()
    changes.project = ""
    changes.priority = ""
    changes.tag = .remove("")
    let invalid = changes
    await #expect(throws: TaskManagementError.invalidTag("")) { try await manager.applySelection(ids: [original.id], changes: invalid) }
    #expect(try await manager.task(id: original.id) == original)
    changes.tag = nil
    #expect(try changes.modifies(tasks: [original]))
    let saved = try #require(try await manager.applySelection(ids: [original.id], changes: changes).first)
    #expect(saved.attributes["priority"] == nil && saved.attributes["project"] == nil)
    #expect(saved.attributes["tag_"] == "unknown")
}
