import Foundation
import Testing
import TskCore

@Test func findActionCombinesLiteralFiltersAndExcludesChildrenAndDeletedTasks() async throws {
    let selected = TaskRecord(id: UUID(), attributes: ["description": "Book TRAIN tickets", "status": "pending", "project": "Travel", "tag_rail": "", "tag_trip": "", "priority": "H"])
    var child = TaskRecord(id: UUID(), attributes: selected.attributes)
    child.attributes["project"] = "Travel.Rail"
    var deleted = TaskRecord(id: UUID(), attributes: selected.attributes)
    deleted.attributes["status"] = "deleted"
    let manager = TaskManager(replica: FindActionReplica(records: [child, deleted, selected]))
    let input = FindTasksInput(description: "train", project: "Travel", tags: ["trip", "rail"], priority: "H")
    #expect(try await manager.findTasks(input).map(\.id) == [selected.id])
    #expect(try await manager.findTasks(FindTasksInput(status: .all)).count == 2)
    #expect(try await manager.findTasks(FindTasksInput(description: "+rail status:pending")).isEmpty)
}

private struct FindActionReplica: TaskReplica {
    let records: [TaskRecord]
    func tasks() async throws -> [TaskRecord] { records }
    func create(id: UUID, attributes: TaskAttributes) async throws -> TaskRecord { throw TaskManagementError.storage("Read-only fixture") }
    func update(id: UUID, changes: TaskAttributePatch) async throws -> TaskRecord { throw TaskManagementError.storage("Read-only fixture") }
}

@Test func findURLParsesNamedRangesAndPaginationAndReturnsListCallbacks() throws {
    let request = try TaskActionURL(url: #require(URL(string: "tsk://find?description=TRAIN&project=Travel&tags=rail&tags=trip&status=all&priority=H&scheduled-from=2026-11-05T08:30:00Z&scheduled-through=2026-11-05T10:30:00%2B02:00&deadline-through=2026-11-06T08:30:00Z&waiting-until-from=2026-11-04T08:30:00Z&sort=deadline-asc&limit=2&offset=1")))
    guard case .find(let input) = request else { Issue.record("Expected Find"); return }
    #expect(input.description == "TRAIN" && input.project == "Travel" && input.tags == ["rail", "trip"])
    #expect(input.status == .all && input.priority == "H" && input.sort == .deadline)
    #expect(input.limit == 2 && input.offset == 1)
    #expect(input.scheduled.from == input.scheduled.through)
    let callbacks = try TaskActionCallbacks(url: #require(URL(string: "tsk://find?x-success=caller%3A%2F%2Fdone")))
    let record = TaskRecord(id: UUID(), attributes: ["description": "Train", "status": "pending"])
    let url = try #require(try callbacks.successURL(for: [record]))
    let json = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "result" }?.value)
    let payload = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    let tasks = try #require(payload["tasks"] as? [[String: Any]])
    #expect(payload["success"] as? Bool == true && payload["savedLocally"] == nil)
    #expect(tasks.first?["uuid"] as? String == record.id.uuidString)
    #expect(try callbacks.successURL(for: [TaskRecord]()) != nil)
    #expect(throws: TaskActionError.resultTooLarge) { try callbacks.successURL(for: Array(repeating: record, count: 100)) }
    for query in ["filter=status:pending", "status=deleted", "sort=unknown", "offset=-1", "offset=1.5", "limit=0", "limit=-1", "limit=99999999999999999999999999999", "limit=", "limit=1&limit=2", "scheduled-from=2026-11-05", "scheduled-from=2026-11-06T00:00:00Z&scheduled-through=2026-11-05T00:00:00Z", "priority=urgent"] {
        #expect(throws: (any Error).self) { try TaskActionURL(url: #require(URL(string: "tsk://find?" + query))) }
    }
}

@Test func findActionPreservesProjectAndTagUTF8IdentityAndMatchesEveryTag() async throws {
    let composed = TaskRecord(id: UUID(), attributes: ["description": "One", "status": "pending", "project": "café", "tag_café": "", "tag_rail": ""])
    let decomposed = TaskRecord(id: UUID(), attributes: ["description": "Two", "status": "pending", "project": "cafe\u{301}", "tag_cafe\u{301}": "", "tag_rail": ""])
    let manager = TaskManager(replica: FindActionReplica(records: [composed, decomposed]))
    #expect(try await manager.findTasks(FindTasksInput(project: "café")).map(\.id) == [composed.id])
    #expect(try await manager.findTasks(FindTasksInput(tags: ["cafe\u{301}", "rail"])).map(\.id) == [decomposed.id])
    #expect(try await manager.findTasks(FindTasksInput(project: "café", tags: ["cafe\u{301}"])).isEmpty)
    #expect(try await manager.findTasks(FindTasksInput(tags: ["rail", "missing"])).isEmpty)
    #expect(try await manager.findTasks(FindTasksInput(project: "Café")).isEmpty)
}

@Test func findActionUsesInclusiveIndependentRangesAndRejectsInvalidInputs() async throws {
    let instant = Date(timeIntervalSince1970: 1000)
    let record = TaskRecord(id: UUID(), attributes: ["description": "Dates", "status": "pending", "scheduled": "1000", "due": "2000", "wait": "500"])
    let manager = TaskManager(replica: FindActionReplica(records: [record, TaskRecord(id: UUID(), attributes: ["description": "Undated", "status": "pending"])]))
    let matching = FindTasksInput(scheduled: TaskDateRange(from: instant, through: instant), deadline: TaskDateRange(from: Date(timeIntervalSince1970: 2000)), waitingUntil: TaskDateRange(through: Date(timeIntervalSince1970: 500)))
    #expect(try await manager.findTasks(matching).map(\.id) == [record.id])
    #expect(try await manager.findTasks(FindTasksInput(scheduled: TaskDateRange(from: Date(timeIntervalSince1970: 1001)))).isEmpty)
    #expect(try await manager.findTasks(FindTasksInput(deadline: TaskDateRange(through: instant))).isEmpty)
    #expect(try await manager.findTasks(FindTasksInput(waitingUntil: TaskDateRange(from: instant))).isEmpty)
    for invalid in [FindTasksInput(scheduled: TaskDateRange(from: instant, through: .distantPast)), FindTasksInput(deadline: TaskDateRange(from: Date(timeIntervalSince1970: .infinity))), FindTasksInput(waitingUntil: TaskDateRange(through: Date(timeIntervalSince1970: .nan))), FindTasksInput(limit: 0), FindTasksInput(limit: -1), FindTasksInput(offset: -1)] {
        await #expect(throws: (any Error).self) { try await manager.findTasks(invalid) }
    }
}

@Test func findActionSortsNumericallyWithStableUUIDTiesThenPaginatesWithoutACap() async throws {
    let a = TaskRecord(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, attributes: ["description": "A", "status": "pending", "entry": "9", "scheduled": "100", "due": "100", "wait": "100", "priority": "H"])
    let b = TaskRecord(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, attributes: ["description": "B", "status": "completed", "entry": "10", "scheduled": "9", "due": "9", "wait": "9", "priority": "L"])
    let c = TaskRecord(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, attributes: ["description": "C", "status": "pending", "entry": "10"])
    let manager = TaskManager(replica: FindActionReplica(records: [c, a, b]))
    #expect(try await manager.findTasks().map(\.id) == [c.id, a.id])
    #expect(try await manager.findTasks(FindTasksInput(status: .completed)).map(\.id) == [b.id])
    for (sort, expected) in [(FindTaskSort.newest, [b.id, c.id, a.id]), (.oldest, [a.id, b.id, c.id]), (.description, [a.id, b.id, c.id]), (.scheduled, [b.id, a.id, c.id]), (.deadline, [b.id, a.id, c.id]), (.waitingUntil, [b.id, a.id, c.id]), (.priority, [a.id, b.id, c.id])] {
        #expect(try await manager.findTasks(FindTasksInput(status: .all, sort: sort)).map(\.id) == expected)
    }
    #expect(try await manager.findTasks(FindTasksInput(status: .all, limit: 1, offset: 1)).map(\.id) == [c.id])
    #expect(try await manager.findTasks(FindTasksInput(status: .all, limit: Int.max, offset: Int.max)).isEmpty)
    let many = TaskManager(replica: FindActionReplica(records: (0..<501).map { _ in TaskRecord(id: UUID(), attributes: ["description": "Uncapped", "status": "pending"]) }))
    #expect(try await many.findTasks().count == 501)
    #expect(try await many.findTasks(FindTasksInput(offset: 500)).count == 1)
}
