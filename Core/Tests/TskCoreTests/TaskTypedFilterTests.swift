import Foundation
import Testing
import TskCore

@Test func numericCustomPredicatesUseConfiguredTypesAndUpdateSavedMembership() async throws {
    let manager = TaskManager(replica: TestReplica(), viewDefinitions: TypedFilterViewStore(), attributeDefinitions: AttributeDefinitionTestStore())
    _ = try await manager.saveAttributeDefinition(name: "score", type: .numeric)
    let missing = try await manager.create(TaskDraft(description: "Missing"))
    let zero = try await manager.create(TaskDraft(description: "Zero", attributes: ["score": "0"]))
    let positive = try await manager.create(TaskDraft(description: "Positive", attributes: ["score": "10", "unfamiliar": "keep"]))
    let negative = try await manager.create(TaskDraft(description: "Negative", attributes: ["score": "-2"]))
    #expect(Set(try await manager.tasks(filter: "score.below:0").map(\.id)) == [missing.id, negative.id])
    #expect(try await manager.tasks(filter: "score.is:0").map(\.id) == [zero.id])
    let saved = try await manager.saveView(name: "High scores", expression: "score.above:2")
    #expect(try await manager.tasks(filter: saved.expression).map(\.id) == [positive.id])
    _ = try await manager.updateUserAttributes(id: positive.id, changes: ["score": "1"])
    #expect(try await manager.tasks(filter: saved.expression).isEmpty)
    #expect(try await manager.task(id: positive.id).attributes["unfamiliar"] == "keep")
}

private actor TypedFilterViewStore: TaskViewDefinitionsStore {
    private var definitions: [SavedTaskView] = []
    func load() async throws -> [SavedTaskView] { definitions }
    func save(_ definitions: [SavedTaskView]) async throws { self.definitions = definitions }
}

@Test func durationCustomPredicatesUseSecondsAndKeepMissingAndZeroSemantics() async throws {
    let manager = TaskManager(replica: TestReplica(), attributeDefinitions: AttributeDefinitionTestStore())
    _ = try await manager.saveAttributeDefinition(name: "effort", type: .duration)
    let missing = try await manager.create(TaskDraft(description: "Missing duration"))
    let zero = try await manager.create(TaskDraft(description: "Zero duration", attributes: ["effort": "PT0S"]))
    let twoHours = try await manager.create(TaskDraft(description: "Two hours", attributes: ["effort": "2h"]))
    #expect(try await manager.tasks(filter: "effort.is:120min").map(\.id) == [twoHours.id])
    #expect(Set(try await manager.tasks(filter: "effort.is:PT0S").map(\.id)) == [missing.id, zero.id])
    #expect(try await manager.tasks(filter: "effort.above:PT1H").map(\.id) == [twoHours.id])
    #expect(try await manager.tasks(filter: "effort.above:PT0S").isEmpty)
}

@Test func uuidAndDefaultPriorityFiltersRetainCaseExactIdentityAndConfiguredOrdering() async throws {
    let manager = TaskManager(replica: TestReplica(), attributeDefinitions: AttributeDefinitionTestStore())
    _ = try await manager.saveAttributeDefinition(name: "reference", type: .uuid)
    let high = try await manager.create(TaskDraft(description: "High", attributes: ["priority": "H", "reference": "ABCDEF12"]))
    let low = try await manager.create(TaskDraft(description: "Low", attributes: ["priority": "L", "reference": "abcdef12-1234-1234-1234-123456789012"]))
    _ = try await manager.create(TaskDraft(description: "Missing"))
    #expect(try await manager.tasks(filter: "reference:abcdef12").map(\.id) == [low.id])
    #expect(try await manager.tasks(filter: "reference.is:ABCDEF12").map(\.id) == [high.id])
    #expect(try await manager.tasks(filter: "priority.above:M").map(\.id) == [high.id])
    #expect(try await manager.tasks(filter: "priority.below:M").contains { $0.id == low.id })
}

@Test func declaredStringValueOrderingIsByteExactAndValidatesChangedValuesOnly() async throws {
    let definitions = AttributeDefinitionTestStore()
    let replica = TestReplica()
    let manager = TaskManager(replica: replica, attributeDefinitions: definitions)
    _ = try await manager.saveAttributeDefinition(name: "rating", type: .string, values: ["low", "mid", "high"])
    let low = try await manager.create(TaskDraft(description: "Declared first", attributes: ["rating": "low"]))
    let missing = try await manager.create(TaskDraft(description: "Absent"))
    _ = try await manager.create(TaskDraft(description: "Declared last", attributes: ["rating": "high"]))
    #expect(Set(try await manager.tasks(filter: "rating.above:mid").map(\.id)) == [low.id, missing.id])
    await #expect(throws: (any Error).self) { try await manager.updateUserAttributes(id: low.id, changes: ["rating": "other"]) }
    _ = try await manager.saveAttributeDefinition(name: "spelling", type: .string, values: ["é", "e\u{301}"])
    let task = try await manager.create(TaskDraft(description: "Byte values", attributes: ["spelling": "e\u{301}"]))
    #expect(try await manager.tasks(filter: "spelling.below:é").map(\.id) == [task.id])
    #expect(try await manager.attributeDefinitions().first { $0.name == UTF8String("spelling") }?.values?.count == 2)
}

@Test func invalidImportedTypedValuesReportTheirTaskWithoutDroppingRawData() async throws {
    let replica = TestReplica()
    let manager = TaskManager(replica: replica, attributeDefinitions: AttributeDefinitionTestStore())
    for type in [TaskAttributeType.numeric, .date, .duration, .uuid] {
        let name = "custom_" + type.rawValue
        _ = try await manager.saveAttributeDefinition(name: name, type: type)
        let imported = try await replica.create(id: UUID(), attributes: ["description": "Imported \(type.rawValue)", "status": "pending", name: "invalid", "foreign": "keep"])
        await #expect(throws: TaskFilterError.invalidStoredValue(imported.id, name, type)) { try await manager.tasks(filter: "\(name).any:") }
        #expect(try await manager.task(id: imported.id).attributes[name] == "invalid")
        _ = try await manager.update(id: imported.id, changes: ["description": "Retained \(type.rawValue)"])
        #expect(try await manager.task(id: imported.id).attributes["foreign"] == "keep")
    }
    await #expect(throws: TaskFilterError.unknownAttribute("unregistered")) { try await manager.tasks(filter: "unregistered:1") }
    #expect(try await manager.tasks(filter: "description:Retained").count == 4)
}
