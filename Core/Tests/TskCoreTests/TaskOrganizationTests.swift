import Foundation
import Testing
@testable import TskCore

@Test func organizationMovesTaskBetweenExactProjectViewsAndPreservesOtherAttributes() async throws {
    let manager = TaskManager(replica: TestReplica())
    var draft = TaskDraft(description: "Organize work", attributes: ["opaque": "retain"])
    draft.project = "Home"
    draft.priority = "H"
    try draft.addTag("errands")
    let original = try await manager.create(draft)
    #expect(original.tags == ["errands"])
    #expect(try await manager.tasks(query: .unfinished, project: .project("Home")) == [original])
    let revised = try await manager.update(id: original.id, changes: ["project": "Home.Office", "priority": "M", "tag_errands": nil, "tag_next": ""])
    #expect(try await manager.tasks(query: .unfinished, project: .project("Home")).isEmpty)
    #expect(try await manager.tasks(query: .unfinished, project: .project("Home.Office")) == [revised])
    #expect(try await manager.projects() == ["Home.Office"])
    #expect(revised.id == original.id)
    #expect(revised.tags == ["next"])
    #expect(revised.attributes["opaque"] == "retain")
    #expect(revised.attributes["tags"] == "next")
}

@Test func invalidOrganizationChangesFailWithoutReplacingExistingFields() async throws {
    let manager = TaskManager(replica: TestReplica())
    let original = try await manager.create(TaskDraft(description: "Keep original", attributes: ["priority": "H", "opaque": "retain"]))
    await #expect(throws: TaskManagementError.invalidPriority("urgent")) {
        try await manager.update(id: original.id, changes: ["priority": "urgent", "project": "Changed"])
    }
    await #expect(throws: TaskManagementError.invalidTag("bad tag")) {
        try await manager.update(id: original.id, changes: ["tag_bad tag": ""])
    }
    #expect(try await manager.task(id: original.id) == original)
}

@Test func legacyTagStringAndUnrecognizedPriorityDoNotOverrideAuthoritativeTagsOrBlockUnrelatedEdits() async throws {
    let replica = TestReplica()
    let imported = try await replica.create(id: UUID(), attributes: ["description": "Imported", "status": "pending", "priority": "custom", "tag_home": "x", "tags": "ghost", "opaque": "retain"])
    let manager = TaskManager(replica: replica)
    let revised = try await manager.update(id: imported.id, changes: ["description": "Revised"])
    #expect(revised.tags == ["home"])
    #expect(revised.priority == "custom")
    #expect(revised.attributes["tags"] == "ghost")
    #expect(revised.attributes["opaque"] == "retain")
    #expect(try await manager.tasks(project: .unassigned) == [revised])
}

@Test func organizationCanBeClearedWithoutChangingOtherTaskFields() async throws {
    let manager = TaskManager(replica: TestReplica())
    let original = try await manager.create(TaskDraft(description: "Organized", attributes: ["project": "Home", "priority": "L", "tag_home": "x", "opaque": "retain"]))
    let cleared = try await manager.update(id: original.id, changes: ["project": "", "priority": "", "tag_home": nil])
    #expect(cleared.project.isEmpty)
    #expect(cleared.priority.isEmpty)
    #expect(cleared.tags.isEmpty)
    #expect(cleared.attributes["tags"] == nil)
    #expect(cleared.attributes["opaque"] == "retain")
    #expect(try await manager.tasks(project: .unassigned) == [cleared])
}

@Test func projectNamesRetainExactWhitespaceAsWellAsCase() async throws {
    let manager = TaskManager(replica: TestReplica())
    let spaced = try await manager.create(TaskDraft(description: "Exact name", attributes: ["project": " Home "]))
    #expect(spaced.project == " Home ")
    #expect(try await manager.tasks(project: .project("Home")).isEmpty)
    #expect(try await manager.tasks(project: .project(" Home ")) == [spaced])
}
