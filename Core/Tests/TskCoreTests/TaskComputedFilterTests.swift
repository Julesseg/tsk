import Foundation
import Testing
import TskCore

@Test func computedUrgencyUsesPinnedFloatPrecisionAndFullDependencyContext() async throws {
    let replica = TestReplica()
    let instant = Date(timeIntervalSince1970: 1792144800)
    let manager = TaskManager(replica: replica, now: { instant })
    let medium = try await manager.create(TaskDraft(description: "Medium", attributes: ["priority": "M"]))
    #expect(try await manager.tasks(filter: "urgency.is:3.9").isEmpty)
    #expect(try await manager.tasks(filter: "urgency.above:3.9").map(\.id) == [medium.id])
    let prerequisite = try await manager.create(TaskDraft(description: "Outside selected project", attributes: ["project": "Other"]))
    let dependent = try await manager.create(TaskDraft(description: "Blocked", attributes: ["project": "Work"]))
    _ = try await manager.addDependency(id: dependent.id, prerequisiteID: prerequisite.id)
    #expect(try await manager.tasks(filter: "project:Work and urgency.below:0").map(\.id) == [dependent.id])
    _ = try await manager.complete(id: prerequisite.id)
    #expect(try await manager.tasks(filter: "project:Work and urgency.below:0").isEmpty)
}

@Test func rawExpressionsCombineComputedFieldsArithmeticAndExistingPredicates() async throws {
    let manager = TaskManager(replica: TestReplica(), now: { Date(timeIntervalSince1970: 1792144800) })
    let medium = try await manager.create(TaskDraft(description: "Medium", attributes: ["priority": "M"]))
    _ = try await manager.create(TaskDraft(description: "Low", attributes: ["priority": "L"]))
    #expect(try await manager.tasks(filter: "urgency + 1 > 4.9").map(\.id) == [medium.id])
    #expect(try await manager.tasks(filter: "(urgency * 2 > 7.8) and priority.is:M").map(\.id) == [medium.id])
    #expect(try await manager.tasks(filter: "urgency.above:3+1").isEmpty)
    #expect(try await manager.tasks(filter: "description == Medium and !(urgency < 3)").map(\.id) == [medium.id])
}

@Test func expressionPrecedenceRuntimeFailuresAndDesktopIDsRemainExplicit() async throws {
    let manager = TaskManager(replica: TestReplica(), now: { Date(timeIntervalSince1970: 1792144800) })
    let task = try await manager.create(TaskDraft(description: "Arithmetic", attributes: ["priority": "M"]))
    for expression in ["urgency - urgency + 7 / 2 == 3", "urgency - urgency + 7.0 / 2 == 3.5", "urgency - urgency + 2 ^ 3 ^ 2 == 512", "urgency - urgency + -2 ^ 2 == -4", "urgency - urgency + 5.5 % 2 == 1.5", "urgency > (urgency - urgency + 3.0 + 0.9)"] {
        #expect(try await manager.tasks(filter: expression).map(\.id) == [task.id], "\(expression)")
    }
    for expression in ["urgency / 0 > 0", "urgency ^ 2.0 > 0", "false and urgency / 0 > 0", "urgency > (3.0 + 1.0)"] {
        await #expect(throws: TaskFilterError.self) { try await manager.tasks(filter: expression) }
    }
    let empty = TaskManager(replica: TestReplica())
    await #expect(throws: TaskFilterError.self) { try await empty.validateFilter("urgency / 0 > 0") }
}

@Test func typedArithmeticPreservesPinnedTemporalCastsAndByteExactIdentity() async throws {
    let replica = TestReplica()
    let id = UUID(uuidString: "abcdef12-1234-1234-1234-123456789012")!
    _ = try await replica.create(id: id, attributes: ["description": "Typed arithmetic", "status": "pending", "entry": "1792144800", "effort": "PT1H", "score": "-2", "note": "abc", "annotation_1792144800": "Note"])
    let manager = TaskManager(replica: replica)
    let schema = TaskFilterSchema.standard.adding([TaskAttributeDefinition(name: "score", type: .numeric), TaskAttributeDefinition(name: "effort", type: .duration), TaskAttributeDefinition(name: "note", type: .string)])
    for expression in ["effort * -0.5 > 1h", "effort / -0.5 > 1h", "score + effort > 1h", "score - effort == -3602", "true + score == -1", "true * score == -2", "annotations.1.entry.year == 2026", "annotations.1.description == 'Note'", "note - 'x' == \"abc-'x'\"", "abcdef12"] {
        #expect(try await manager.tasks(filter: expression, schema: schema).map(\.id) == [id], "\(expression)")
    }
    #expect(try await manager.tasks(filter: "uuid == abcdef12", schema: schema).isEmpty)
    #expect(try await manager.tasks(filter: "uuid = 'abcdef12'", schema: schema).map(\.id) == [id])
}

@Test func combinedExpressionsSurfaceReferencedInvalidValuesEvenWhenAnotherPredicateIsFalse() async throws {
    let replica = TestReplica()
    let id = UUID()
    _ = try await replica.create(id: id, attributes: ["description": "Imported invalid number", "status": "pending", "score": "invalid", "foreign": "keep"])
    let manager = TaskManager(replica: replica)
    let schema = TaskFilterSchema.standard.adding([TaskAttributeDefinition(name: "score", type: .numeric)])
    for expression in ["status:completed and score.above:0", "status:pending or score.above:0", "status:completed and score + 1 > 0"] {
        await #expect(throws: TaskFilterError.invalidStoredValue(id, "score", .numeric)) { try await manager.tasks(filter: expression, schema: schema) }
    }
    #expect(try await manager.task(id: id).attributes["foreign"] == "keep")
}

@Test func uuidSelectorUnionUsesFullReplicaAndRetainsPinnedBooleanOperandMeaning() async throws {
    let replica = TestReplica()
    let first = UUID(uuidString: "abcdef12-1234-1234-1234-123456789012")!
    let second = UUID(uuidString: "12345678-1234-1234-1234-123456789012")!
    _ = try await replica.create(id: first, attributes: ["description": "Active completed", "status": "completed", "start": "1792144800"])
    _ = try await replica.create(id: second, attributes: ["description": "Pending", "status": "pending"])
    let manager = TaskManager(replica: replica)
    #expect(Set(try await manager.tasks(filter: "abcdef12 12345678").map(\.id)) == [first, second])
    #expect(try await manager.tasks(filter: "abcdef12 +ACTIVE").map(\.id) == [first])
    #expect(try await manager.tasks(filter: "uuid == abcdef12").isEmpty)
}

@Test func finalExpressionSelectionPreservesTaskwarriorBooleanResultSlot() async throws {
    let manager = TaskManager(replica: TestReplica())
    let task = try await manager.create(TaskDraft(description: "project", attributes: ["project": "Work"]))
    #expect(try await manager.tasks(filter: "urgency + 1").isEmpty)
    #expect(try await manager.tasks(filter: "false + 2").isEmpty)
    #expect(try await manager.tasks(filter: "true + 2").map(\.id) == [task.id])
    #expect(try await manager.tasks(filter: "project").isEmpty)
    #expect(try await manager.tasks(filter: "project or +home").map(\.id) == [task.id])
}
