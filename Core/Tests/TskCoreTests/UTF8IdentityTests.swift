import Foundation
import Testing
@testable import TskCore

@Test func taskManagementPreservesDistinctUTF8KeysTagsAndProjects() async throws {
    let manager = TaskManager(replica: TestReplica())
    let composed = "café"
    let decomposed = "cafe\u{301}"
    var draft = TaskDraft(description: "Unicode work")
    draft.attributes[composed] = "composed field"
    draft.attributes[decomposed] = "decomposed field"
    draft.project = composed
    try draft.addTag(composed)
    try draft.addTag(decomposed)
    let original = try await manager.create(draft)
    let second = try await manager.create(TaskDraft(description: "Other project", attributes: ["project": decomposed]))
    #expect(original.attributes[composed] == "composed field")
    #expect(original.attributes[decomposed] == "decomposed field")
    #expect(original.tags.count == 2)
    #expect(try await manager.projects().count == 2)
    #expect(try await manager.tasks(project: .project(composed)).map(\.id) == [original.id])
    #expect(try await manager.tasks(project: .project(decomposed)).map(\.id) == [second.id])
    _ = try await manager.update(id: original.id, changes: ["description": "Edited", "tag_\(decomposed)": nil])
    let revised = try await manager.task(id: original.id)
    #expect(revised.attributes[composed] == "composed field")
    #expect(revised.attributes[decomposed] == "decomposed field")
    #expect(revised.attributes["tag_\(composed)"] != nil)
    #expect(revised.attributes["tag_\(decomposed)"] == nil)
}

@Test func editingUnicodeSpellingCreatesByteExactAttributePatch() async throws {
    let manager = TaskManager(replica: TestReplica())
    let original = try await manager.create(TaskDraft(description: "Original", attributes: ["café": "one", "cafe\u{301}": "two", "project": "café"]))
    var edited = original.attributes
    edited["project"] = "cafe\u{301}"
    edited.removeValue(forKey: "cafe\u{301}")
    let saved = try await manager.update(id: original.id, changes: edited.changes(comparedTo: original.attributes))
    #expect(saved.project.matchesBytes("cafe\u{301}"))
    #expect(saved.attributes["café"] == "one")
    #expect(saved.attributes["cafe\u{301}"] == nil)
}
