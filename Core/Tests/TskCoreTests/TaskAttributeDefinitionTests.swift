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
    var writesFail = false
    func setWriteFailure(_ failing: Bool) { writesFail = failing }
    func load() async throws -> [TaskAttributeDefinition] { values }
    func save(_ definitions: [TaskAttributeDefinition]) async throws {
        if writesFail { throw TaskManagementError.storage("Metadata disk is full") }
        values = definitions
    }
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

@Test func registeredValuesValidateOnCommonMutationsAndUnchangedInvalidValuesSurvive() async throws {
    let replica = TestReplica()
    let manager = TaskManager(replica: replica, attributeDefinitions: AttributeDefinitionTestStore())
    _ = try await manager.saveAttributeDefinition(name: "score", type: .numeric)
    _ = try await manager.saveAttributeDefinition(name: "reference", type: .uuid)
    _ = try await manager.saveAttributeDefinition(name: "effort", type: .duration)
    let imported = try await replica.create(id: UUID(), attributes: ["description": "Imported", "status": "pending", "score": "not a number", "reference": "foreign opaque value", "orphan": "keep"])
    let edited = try await manager.update(id: imported.id, changes: ["description": "Revised"])
    #expect(edited.attributes["score"] == "not a number")
    #expect(edited.attributes["reference"] == "foreign opaque value")
    #expect(edited.attributes["orphan"] == "keep")
    await #expect(throws: (any Error).self) { try await manager.update(id: imported.id, changes: ["score": "NaN"]) }
    await #expect(throws: (any Error).self) { try await manager.create(TaskDraft(description: "Invalid", attributes: ["score": "001"])) }
    await #expect(throws: (any Error).self) { try await manager.updateUserAttributes(id: imported.id, changes: ["reference": "xyz"]) }
    await #expect(throws: (any Error).self) { try await manager.updateUserAttributes(id: imported.id, changes: ["effort": "1h30min"]) }
    await #expect(throws: TaskAttributeError.missingDefinition("orphan")) { try await manager.updateUserAttributes(id: imported.id, changes: ["orphan": "Overwritten"]) }
    #expect(try await manager.task(id: imported.id) == edited)
    let cleared = try await manager.updateUserAttributes(id: imported.id, changes: ["score": nil])
    #expect(cleared.attributes["score"] == nil)
    #expect(cleared.attributes["reference"] == "foreign opaque value")
}

@Test func effectiveLocalSchemaDistinguishesUserAttributesFromBuiltinAndIndependentKeys() async throws {
    let manager = TaskManager(replica: TestReplica(), attributeDefinitions: AttributeDefinitionTestStore())
    _ = try await manager.saveAttributeDefinition(name: "e\u{301}", type: .string)
    let task = try await manager.create(TaskDraft(description: "Schema", attributes: ["e\u{301}": "value"]))
    #expect(try await manager.tasks(filter: "e\u{301}.is:value").map(\.id) == [task.id])
    let schema = try await manager.effectiveFilterSchema()
    #expect(schema.isUserDefined("e\u{301}"))
    #expect(!schema.isUserDefined("é"))
    #expect(schema.isUserDefined("priority"))
    #expect(!schema.isUserDefined("description"))
    #expect(schema.contains("template"))
    #expect(schema.contains("last"))
    #expect(schema.contains("annotation_bad"))
    #expect(schema.contains("dep_bad"))
    #expect(schema.contains("tag_\u{301}"))
    for name in ["due", "priority", "uuid", "tag_test", "annotation_1"] {
        await #expect(throws: TaskAttributeError.reservedName(name)) { try await manager.saveAttributeDefinition(name: name, type: .string) }
    }
    for name in ["", "1invalid", "has space", "field.type"] {
        await #expect(throws: TaskAttributeError.invalidName(name)) { try await manager.saveAttributeDefinition(name: name, type: .string) }
    }
}

@Test func uuidAttributesFollowPinnedTaskwarriorPrefixAndBoundaryValidation() async throws {
    let manager = TaskManager(replica: TestReplica(), attributeDefinitions: AttributeDefinitionTestStore())
    _ = try await manager.saveAttributeDefinition(name: "reference", type: .uuid)
    let task = try await manager.create(TaskDraft(description: "UUID semantics"))
    for value in ["abcdef12", "abcdef12-", "7ACEF642-1530-4F93-BBD3-866A5D0966F9", "abcdef12 text", "abcdef12+garbage"] {
        let saved = try await manager.updateUserAttributes(id: task.id, changes: ["reference": value])
        #expect(saved.attributes["reference"]?.matchesBytes(value) == true)
    }
    for value in ["xyz", "abcdef1", "abcdef12junk", "ＦＦＦＦＦＦＦＦ"] {
        await #expect(throws: (any Error).self) { try await manager.updateUserAttributes(id: task.id, changes: ["reference": value]) }
    }
}

@Test func unavailableAndFailedDefinitionStorageRemainExplicitAndReleaseTheMutationGate() async throws {
    let absent = TaskManager(replica: TestReplica())
    await #expect(throws: TaskAttributeError.storageNotConfigured) { try await absent.attributeDefinitions() }
    let store = AttributeDefinitionTestStore()
    let manager = TaskManager(replica: TestReplica(), attributeDefinitions: store)
    let original = try await manager.saveAttributeDefinition(name: "field", label: "Original", type: .string)
    await store.setWriteFailure(true)
    await #expect(throws: TaskManagementError.storage("Metadata disk is full")) { try await manager.saveAttributeDefinition(name: "field", label: "Unsaved", type: .date) }
    await #expect(throws: TaskManagementError.storage("Metadata disk is full")) { try await manager.deleteAttributeDefinition(name: "field") }
    #expect(try await manager.attributeDefinitions() == [original])
    await store.setWriteFailure(false)
    _ = try await manager.saveAttributeDefinition(name: "next", type: .numeric)
    #expect(try await manager.attributeDefinitions().count == 2)
}
