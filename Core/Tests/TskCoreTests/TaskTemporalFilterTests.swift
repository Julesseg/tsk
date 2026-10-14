import Foundation
import Testing
@testable import TskCore

@Test func datePredicatesKeepDueSeparateFromPlannedAndReevaluateTheClock() async throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    let clock = TemporalFilterClock(calendar.date(from: DateComponents(year: 2027, month: 3, day: 27, hour: 12))!)
    let manager = TaskManager(replica: TestReplica(), now: { clock.date }, calendar: calendar)
    let due = try await manager.create(TaskDraft(description: "Deadline", attributes: ["due": "\(Int(calendar.date(from: DateComponents(year: 2027, month: 3, day: 27, hour: 23))!.timeIntervalSince1970))"]))
    _ = try await manager.create(TaskDraft(description: "Planned only", attributes: ["scheduled": "\(Int(clock.date.timeIntervalSince1970))"]))
    #expect(try await manager.tasks(filter: "due:today").map(\.id) == [due.id])
    #expect(try await manager.tasks(filter: "+TODAY").map(\.id) == [due.id])
    #expect(try await manager.tasks(filter: "due.before:tomorrow").map(\.id) == [due.id])
    clock.date = calendar.date(from: DateComponents(year: 2027, month: 3, day: 28, hour: 12))!
    #expect(try await manager.tasks(filter: "due:today").isEmpty)
    #expect(try await manager.tasks(filter: "+YESTERDAY").map(\.id) == [due.id])
    #expect(try await manager.tasks(filter: "due.before:now+1d").map(\.id) == [due.id])
}

private final class TemporalFilterClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ date: Date) { value = date }
    var date: Date {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

@Test func virtualAvailabilityAndDatePredicatesPublishClockReevaluationBoundaries() async throws {
    let clock = TemporalFilterClock(Date(timeIntervalSince1970: 1000))
    let manager = TaskManager(replica: TestReplica(), now: { clock.date })
    let waiting = try await manager.create(TaskDraft(description: "Waiting", attributes: ["wait": "1001", "scheduled": "1000"]))
    #expect(try await manager.tasks(filter: "+WAITING").map(\.id) == [waiting.id])
    #expect(try await manager.tasks(filter: "+READY").isEmpty)
    #expect(try await manager.viewSnapshot(filter: "+READY").nextEvaluation == Date(timeIntervalSince1970: 1001))
    clock.date = Date(timeIntervalSince1970: 1001)
    #expect(try await manager.tasks(filter: "+WAITING").isEmpty)
    #expect(try await manager.tasks(filter: "+READY").map(\.id) == [waiting.id])
    let prerequisite = try await manager.create(TaskDraft(description: "Prerequisite"))
    _ = try await manager.addDependency(id: waiting.id, prerequisiteID: prerequisite.id)
    #expect(try await manager.tasks(filter: "+BLOCKED").map(\.id) == [waiting.id])
    #expect(try await manager.tasks(filter: "+BLOCKING").map(\.id) == [prerequisite.id])
    _ = try await manager.complete(id: prerequisite.id)
    #expect(try await manager.tasks(filter: "+READY").map(\.id) == [waiting.id])
    #expect(try await manager.tasks(filter: "+UNBLOCKED and status:completed").map(\.id) == [prerequisite.id])
}
