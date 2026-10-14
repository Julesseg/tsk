import Foundation
import Testing
import TskCore

@Test func reschedulingOneDateRolePreservesTheOtherDateAndEveryOpaqueAttribute() async throws {
    let manager = TaskManager(replica: TestReplica())
    let original = try await manager.create(TaskDraft(description: "Catch train", attributes: ["scheduled": "1792051200", "due": "1792137600", "opaque": "preserve", "start": "1792040000"]))
    let planned = try await manager.reschedule(id: original.id, role: .planned, to: Date(timeIntervalSince1970: 1792224000))
    #expect(planned.id == original.id)
    #expect(planned.attributes["scheduled"] == "1792224000")
    #expect(planned.attributes["due"] == "1792137600")
    #expect(planned.attributes["opaque"] == "preserve")
    #expect(planned.attributes["start"] == "1792040000")
    let deadline = try await manager.reschedule(id: original.id, role: .deadline, to: Date(timeIntervalSince1970: 1792314000))
    #expect(deadline.attributes["scheduled"] == "1792224000")
    #expect(deadline.attributes["due"] == "1792314000")
    let cleared = try await manager.reschedule(id: original.id, role: .planned, to: nil)
    #expect(cleared.attributes["scheduled"] == nil)
    #expect(cleared.attributes["due"] == "1792314000")
    #expect(cleared.attributes["opaque"] == "preserve")
}

@Test func invalidAutomationDatesAndUnsupportedTaskKindsReturnErrorsWithoutChangingTheTask() async throws {
    let replica = TestReplica()
    let manager = TaskManager(replica: replica)
    let ordinary = try await manager.create(TaskDraft(description: "Keep original", attributes: ["due": "1792137600", "opaque": "retain"]))
    for value in [Double.nan, .infinity, 253402300800] {
        await #expect(throws: TaskReschedulingError.invalidDate) {
            try await manager.reschedule(id: ordinary.id, role: .deadline, to: Date(timeIntervalSince1970: value))
        }
        #expect(try await manager.task(id: ordinary.id) == ordinary)
    }
    let recurring = try await replica.create(id: UUID(), attributes: ["description": "Existing template", "status": "recurring", "recur": "weekly", "opaque": "preserve"])
    await #expect(throws: TaskManagementError.unsupportedTaskKind) { try await manager.reschedule(id: recurring.id, role: .planned, to: Date()) }
    await #expect(throws: TaskManagementError.unsupportedTaskKind) { try await manager.complete(id: recurring.id) }
    #expect(try await manager.task(id: recurring.id) == recurring)
}

@Test func reschedulingAndCompletionUpdateTodayUpcomingAndCompletedThroughSharedQueries() async throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let manager = TaskManager(replica: TestReplica(), now: { Date(timeIntervalSince1970: 1792144800) }, calendar: calendar)
    let task = try await manager.create(TaskDraft(description: "Move across views", attributes: ["scheduled": "1792144800"]))
    #expect(try await manager.tasks(query: .today).map(\.id) == [task.id])
    _ = try await manager.reschedule(id: task.id, role: .planned, to: Date(timeIntervalSince1970: 1792224000))
    #expect(try await manager.tasks(query: .today).isEmpty)
    #expect(try await manager.tasks(query: .upcoming).map(\.id) == [task.id])
    _ = try await manager.complete(id: task.id)
    #expect(try await manager.tasks(query: .upcoming).isEmpty)
    #expect(try await manager.tasks(query: .unfinished).isEmpty)
    #expect(try await manager.tasks(query: .completed).map(\.id) == [task.id])
}
