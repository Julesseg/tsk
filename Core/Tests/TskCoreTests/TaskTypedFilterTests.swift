import Foundation
import Testing
import TskCore

@Test func explicitDurationSchemaPredicatesUseSecondsAndKeepMissingAndZeroSemantics() async throws {
    let manager = TaskManager(replica: TestReplica())
    let schema = TaskFilterSchema(attributes: [("effort", .duration)])
    let missing = try await manager.create(TaskDraft(description: "Missing duration"))
    let zero = try await manager.create(TaskDraft(description: "Zero duration", attributes: ["effort": "PT0S"]))
    let twoHours = try await manager.create(TaskDraft(description: "Two hours", attributes: ["effort": "2h"]))
    #expect(try await manager.tasks(filter: "effort.is:120min", schema: schema).map(\.id) == [twoHours.id])
    #expect(Set(try await manager.tasks(filter: "effort.is:PT0S", schema: schema).map(\.id)) == [missing.id, zero.id])
    #expect(try await manager.tasks(filter: "effort.above:PT1H", schema: schema).map(\.id) == [twoHours.id])
    #expect(try await manager.tasks(filter: "effort.above:PT0S", schema: schema).isEmpty)
}

@Test func explicitUUIDSchemaAndDefaultPriorityRetainTheirComparisonSemantics() async throws {
    let manager = TaskManager(replica: TestReplica())
    let schema = TaskFilterSchema(attributes: [("reference", .uuid)])
    let high = try await manager.create(TaskDraft(description: "High", attributes: ["priority": "H", "reference": "ABCDEF12"]))
    let low = try await manager.create(TaskDraft(description: "Low", attributes: ["priority": "L", "reference": "abcdef12-1234-1234-1234-123456789012"]))
    _ = try await manager.create(TaskDraft(description: "Missing"))
    #expect(try await manager.tasks(filter: "reference:abcdef12", schema: schema).map(\.id) == [low.id])
    #expect(try await manager.tasks(filter: "reference.is:ABCDEF12", schema: schema).map(\.id) == [high.id])
    #expect(try await manager.tasks(filter: "priority.above:M").map(\.id) == [high.id])
    #expect(try await manager.tasks(filter: "priority.below:M").contains { $0.id == low.id })
}

@Test func invalidImportedTypedValuesReportTheirTaskWithoutDroppingRawData() async throws {
    let replica = TestReplica()
    let manager = TaskManager(replica: replica)
    for type in [TaskFilterAttributeType.numeric, .date, .duration, .uuid] {
        let name = "custom_" + type.rawValue
        let schema = TaskFilterSchema(attributes: [(name, type)])
        let imported = try await replica.create(id: UUID(), attributes: ["description": "Imported \(type.rawValue)", "status": "pending", name: "invalid", "foreign": "keep"])
        await #expect(throws: TaskFilterError.invalidStoredValue(imported.id, name, type)) { try await manager.tasks(filter: "\(name).any:", schema: schema) }
        #expect(try await manager.task(id: imported.id).attributes[name] == "invalid")
        _ = try await manager.update(id: imported.id, changes: ["description": "Retained \(type.rawValue)"])
        #expect(try await manager.task(id: imported.id).attributes["foreign"] == "keep")
    }
    await #expect(throws: TaskFilterError.unknownAttribute("unregistered")) { try await manager.tasks(filter: "unregistered:1") }
    #expect(try await manager.tasks(filter: "description:Retained").count == 4)
}

@Test func finiteNumericAttributesBeyondFloatRangeRemainFilterable() async throws {
    let manager = TaskManager(replica: TestReplica())
    let schema = TaskFilterSchema(attributes: [("score", .numeric)])
    let positive = try await manager.create(TaskDraft(description: "Huge", attributes: ["score": "1e100"]))
    let tiny = try await manager.create(TaskDraft(description: "Tiny", attributes: ["score": "1e-100"]))
    let negative = try await manager.create(TaskDraft(description: "Negative", attributes: ["score": "-1e100"]))
    #expect(positive.attributes["score"] == "1e100")
    for query in ["score.over:0", "score > 0", "score * 2 > 0", "score / 2 > 0", "score > 1e100"] {
        #expect(try await manager.tasks(filter: query, schema: schema).map(\.id) == [positive.id])
    }
    #expect(try await manager.tasks(filter: "score.below:0", schema: schema).map(\.id) == [negative.id])
    #expect(try await manager.tasks(filter: "score.is:1e100", schema: schema).isEmpty)
    #expect(Set(try await manager.tasks(filter: "score + 1 > 0", schema: schema).map(\.id)) == [positive.id, tiny.id])
    #expect(try await manager.tasks(filter: "score - score = 0", schema: schema).map(\.id) == [tiny.id])
    #expect(Set(try await manager.tasks(filter: "score = score", schema: schema).map(\.id)) == [positive.id, tiny.id, negative.id])
}

@Test func numericAttributePrecisionMatchesPinnedFloatAndUUIDOperandPrecedence() async throws {
    let manager = TaskManager(replica: TestReplica())
    let schema = TaskFilterSchema(attributes: [("score", .numeric)])
    let integer = try await manager.create(TaskDraft(description: "Integer boundary", attributes: ["score": "16777217"]))
    let fraction = try await manager.create(TaskDraft(description: "Fraction boundary", attributes: ["score": "1.00000001"]))
    #expect(try await manager.tasks(filter: "score.over:16777216", schema: schema).isEmpty)
    #expect(try await manager.tasks(filter: "score.over:16777216.0", schema: schema).isEmpty)
    #expect(try await manager.tasks(filter: "score.over:1", schema: schema).map(\.id) == [integer.id])
    #expect(Set(try await manager.tasks(filter: "score > 16777216", schema: schema).map(\.id)) == [integer.id, fraction.id])
    for query in ["score > 16777216.0", "score + 0 > 16777216.0"] { #expect(try await manager.tasks(filter: query, schema: schema).isEmpty) }
    #expect(try await manager.tasks(filter: "score.is:16777216.0", schema: schema).map(\.id) == [integer.id])
    #expect(try await manager.tasks(filter: "score.is:1", schema: schema).map(\.id) == [fraction.id])
    #expect(try await manager.tasks(filter: "score + 0 > 1", schema: schema).map(\.id) == [integer.id])
}
