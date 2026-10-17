import Foundation
import Testing
@testable import TskCore

@Test func futureWaitIsVirtualWaitingWhileMatchingTaskRemainsInToday() async throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    let manager = TaskManager(replica: TestReplica(), now: { Date(timeIntervalSince1970: 1791972000) }, calendar: calendar)
    let task = try await manager.create(TaskDraft(description: "Waiting but planned", attributes: ["scheduled": "1791928800", "due": "1792015200", "wait": "1791972001", "start": "1791928800", "opaque": "retain"]))
    let availability = try await manager.availability(id: task.id)
    #expect(availability.isWaiting)
    #expect(!availability.isAvailable)
    #expect(availability.reasons == [.waiting(until: Date(timeIntervalSince1970: 1791972001))])
    #expect(try await manager.tasks(query: .today).map(\.id) == [task.id])
    #expect(try await manager.task(id: task.id).status == "pending")
    #expect(try await manager.task(id: task.id).attributes["scheduled"] == "1791928800")
    #expect(try await manager.task(id: task.id).attributes["due"] == "1792015200")
    #expect(try await manager.task(id: task.id).attributes["start"] == "1791928800")
    #expect(try await manager.task(id: task.id).attributes["opaque"] == "retain")
}

@Test func waitExpiresAtTheExactInstantWithoutChangingStoredStatusOrTodayMembership() async throws {
    let replica = TestReplica()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    let before = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 1791972000) }, calendar: calendar)
    let task = try await before.create(TaskDraft(description: "Becomes available", attributes: ["scheduled": "1791928800", "wait": "1791972001"]))
    #expect(try await before.availability(id: task.id).isWaiting)
    let exact = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 1791972001) }, calendar: calendar)
    let availability = try await exact.availability(id: task.id)
    #expect(!availability.isWaiting)
    #expect(availability.isAvailable)
    #expect(availability.reasons.isEmpty)
    #expect(try await exact.task(id: task.id) == task)
    #expect(try await exact.tasks(query: .today).map(\.id) == [task.id])
    let after = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 1791972002) }, calendar: calendar)
    #expect(try await after.availability(id: task.id).isAvailable)
}

@Test func waitingEditsAndRemovalPreservePlanningAndNonpendingTasksDoNotBecomeAvailable() async throws {
    let replica = TestReplica()
    let manager = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 1791972000) })
    let task = try await manager.create(TaskDraft(description: "Independent wait", attributes: ["scheduled": "1791928800", "due": "1792015200", "start": "1791928800", "opaque": "retain"]))
    _ = try await manager.update(id: task.id, changes: ["wait": "1792058400"])
    #expect(try await manager.availability(id: task.id).isWaiting)
    _ = try await manager.update(id: task.id, changes: ["wait": "1791971999"])
    #expect(try await manager.availability(id: task.id).isAvailable)
    _ = try await manager.update(id: task.id, changes: ["wait": "1792058400"])
    _ = try await manager.update(id: task.id, changes: ["wait": nil])
    #expect(try await manager.availability(id: task.id).isAvailable)
    let cleared = try await manager.task(id: task.id)
    #expect(cleared.attributes["wait"] == nil)
    #expect(cleared.attributes["scheduled"] == "1791928800")
    #expect(cleared.attributes["due"] == "1792015200")
    #expect(cleared.attributes["start"] == "1791928800")
    #expect(cleared.attributes["opaque"] == "retain")
    _ = try await manager.update(id: task.id, changes: ["wait": "invalid opaque date"])
    #expect(try await manager.task(id: task.id).attributes["wait"] == "invalid opaque date")
    #expect(!((try await manager.availability(id: task.id)).isWaiting))
    _ = try await manager.update(id: task.id, changes: ["wait": "1792058400"])
    _ = try await manager.complete(id: task.id)
    #expect(!((try await manager.availability(id: task.id)).isAvailable))
    #expect(!((try await manager.availability(id: task.id)).isWaiting))
    #expect(try await manager.task(id: task.id).attributes["wait"] == "1792058400")
    for status in ["deleted", "recurring", "unknown"] {
        let record = try await replica.create(id: UUID(), attributes: ["description": "Not available", "status": status, "wait": "1792058400"])
        #expect(!((try await manager.availability(id: record.id)).isAvailable))
        #expect(!((try await manager.availability(id: record.id)).isWaiting))
    }
}
