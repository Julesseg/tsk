import Foundation
import Testing
import TskCore

@Test func localAttributeDefinitionsStayByteExactAndDoNotChangeTasks() async throws {
    let definitions = AttributeDefinitionTestStore()
    let manager = TaskManager(replica: TestReplica(), attributeDefinitions: definitions)
    let original = try await manager.create(TaskDraft(description: "Keep task", attributes: ["unknown": "opaque"]))
    _ = try await manager.saveAttributeDefinition(name: "score", label: "Score", type: .numeric)
    _ = try await manager.saveAttributeDefinition(name: "é", label: "Composed", type: .string)
    _ = try await manager.saveAttributeDefinition(name: "e\u{301}", label: "Decomposed", type: .string)
    let saved = try await manager.attributeDefinitions()
    #expect(saved.count == 3)
    #expect(saved.contains { $0.name == UTF8String("é") })
    #expect(saved.contains { $0.name == UTF8String("e\u{301}") })
    #expect(try await manager.task(id: original.id) == original)
    try await manager.deleteAttributeDefinition(name: "score")
    #expect(try await manager.attributeDefinitions().count == 2)
}

actor AttributeDefinitionTestStore: TaskAttributeDefinitionsStore {
    var values: [TaskAttributeDefinition] = []
    func load() async throws -> [TaskAttributeDefinition] { values }
    func save(_ definitions: [TaskAttributeDefinition]) async throws { values = definitions }
}

@Test func typedAttributeUpdatesValidateOnlyChangedFieldsAndPreserveOpaqueValues() async throws {
    let manager = TaskManager(replica: TestReplica(), attributeDefinitions: AttributeDefinitionTestStore())
    for (name, type) in [("note", TaskAttributeType.string), ("score", .numeric), ("review", .date), ("effort", .duration), ("reference", .uuid)] {
        _ = try await manager.saveAttributeDefinition(name: name, type: type)
    }
    let original = try await manager.create(TaskDraft(description: "Typed fixture", attributes: ["opaque": "keep", "scheduled": "1792144800", "due": "1792231200"]))
    let saved = try await manager.updateUserAttributes(id: original.id, changes: ["note": "  Notes\nkept  ", "score": "-1.25", "review": "2026-10-16T10:00:00Z", "effort": "1.5h", "reference": "abcdef12"])
    #expect(saved.id == original.id)
    #expect(saved.description == original.description)
    #expect(saved.attributes["note"] == "  Notes\nkept  ")
    #expect(saved.attributes["score"] == "-1.25")
    #expect(saved.attributes["review"] == "1792144800")
    #expect(saved.attributes["effort"] == "PT1H30M")
    #expect(saved.attributes["reference"] == "abcdef12")
    #expect(saved.attributes["opaque"] == "keep")
    #expect(saved.attributes["scheduled"] == "1792144800")
    #expect(saved.attributes["due"] == "1792231200")
}
