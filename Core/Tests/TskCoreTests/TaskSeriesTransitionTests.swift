import Foundation
import Testing
@testable import TskCore

@Test func explicitSuccessorTransitionPreservesHistoryIdentityAndOverdueWork() async throws {
    let parent = UUID(), done = UUID(), overdue = UUID(), first = UUID(), second = UUID()
    let template = TaskRecord(id: parent, attributes: ["status": "recurring", "description": "Series", "due": "50", "recur": "monthly", "rtype": "periodic", "mask": "+-WW", "opaque": "preserve", "scheduled": "40", "wait": "45"])
    let history = TaskRecord(id: done, attributes: ["status": "completed", "parent": parent.uuidString, "imask": "0", "due": "50", "end": "60", "opaque": "history"])
    let past = TaskRecord(id: overdue, attributes: ["status": "pending", "parent": parent.uuidString, "imask": "1", "due": "90", "description": "Overdue"])
    let future = TaskRecord(id: first, attributes: ["status": "pending", "parent": parent.uuidString, "imask": "2", "due": "200", "scheduled": "190", "wait": "195", "opaque": "first"])
    let next = TaskRecord(id: second, attributes: ["status": "pending", "parent": parent.uuidString, "imask": "3", "due": "300", "scheduled": "280", "wait": "295", "opaque": "second"])
    let replica = OccurrenceReplica(records: [template, history, past, future, next])
    let manager = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 100) })
    let firstDue = try #require(ISO8601DateFormatter().date(from: "2094-03-31T09:00:00Z"))
    let draft = TaskSeriesTransitionDraft(effectiveDate: Date(timeIntervalSince1970: 150), firstDue: firstDue, recurrence: "monthly", generatorTimeZone: "UTC")
    let preview = try await manager.previewSeriesTransition(id: parent, draft: draft)
    #expect(preview.affected.map(\.id) == [first, second])
    #expect(preview.successor.id != parent)
    #expect(await replica.batches == 0)
    let successor = try await manager.applySeriesTransition(preview)
    #expect(await replica.batches == 1)
    #expect(try await manager.task(id: done) == history)
    #expect(try await manager.task(id: overdue) == past)
    let retired = try await manager.task(id: parent)
    #expect(retired.status == "deleted")
    #expect(retired.attributes["mask"] == "+-XX")
    #expect(retired.attributes["opaque"] == "preserve")
    #expect(successor.attributes["mask"] == "WW")
    #expect(successor.attributes["parent"] == nil && successor.attributes["template"] == nil)
    #expect(try await manager.task(id: first).attributes["parent"] == successor.id.uuidString.lowercased())
    let moved = try await manager.task(id: second)
    #expect(moved.attributes["opaque"] == "second")
    #expect(moved.plannedDate?.timeIntervalSince1970 == moved.deadline!.timeIntervalSince1970 - 20)
    #expect(moved.deadline == ISO8601DateFormatter().date(from: "2094-04-30T09:00:00Z"))
    _ = try await manager.complete(id: overdue)
    #expect(try await manager.task(id: parent).attributes["mask"] == "++XX")
    #expect(try await manager.task(id: done) == history)
    #expect(try await manager.tasks().count == 6)
}

@Test func transitionProjectsExistingIdentitiesUsingPinnedCalendarAndFixedSecondRules() async throws {
    let cases: [(String, String, String, [String])] = [
        ("monthly", "Europe/Paris", "2094-01-31T10:00:00Z", ["2094-01-31T10:00:00Z", "2094-02-28T10:00:00Z", "2094-03-28T09:00:00Z"]),
        ("2m", "Europe/Paris", "2094-01-31T10:00:00Z", ["2094-01-31T10:00:00Z", "2094-03-31T09:00:00Z", "2094-05-31T09:00:00Z"]),
        ("P2M", "Europe/Paris", "2094-01-31T10:00:00Z", ["2094-01-31T10:00:00Z", "2094-03-30T22:00:00Z", "2094-05-30T22:00:00Z"]),
        ("P3M", "Europe/Paris", "2094-01-31T10:00:00Z", ["2094-01-31T10:00:00Z", "2094-04-29T22:00:00Z", "2094-07-29T22:00:00Z"]),
        ("quarterly", "Europe/Paris", "2094-01-31T10:00:00Z", ["2094-01-31T10:00:00Z", "2094-04-30T09:00:00Z", "2094-07-30T09:00:00Z"]),
        ("yearly", "Europe/Paris", "2096-02-29T10:00:00Z", ["2096-02-29T10:00:00Z", "2097-02-28T10:00:00Z", "2098-02-28T10:00:00Z"]),
        ("biannual", "UTC", "2096-02-29T09:00:00Z", ["2096-02-29T09:00:00Z", "2098-03-01T09:00:00Z", "2100-03-01T09:00:00Z"]),
        ("2years", "UTC", "2096-02-29T09:00:00Z", ["2096-02-29T09:00:00Z", "2098-02-28T09:00:00Z", "2100-02-28T09:00:00Z"]),
        ("daily", "Europe/Paris", "2094-03-27T08:00:00Z", ["2094-03-27T08:00:00Z", "2094-03-28T08:00:00Z", "2094-03-29T08:00:00Z"])
    ]
    let formatter = ISO8601DateFormatter()
    for (rule, zone, rawFirst, expected) in cases {
        let parent = UUID()
        let template = TaskRecord(id: parent, attributes: ["status": "recurring", "due": "200", "recur": "weekly", "mask": "---"])
        let children = (0..<3).map { TaskRecord(id: UUID(), attributes: ["status": "pending", "parent": parent.uuidString, "imask": String($0), "due": String(200 + $0)]) }
        let manager = TaskManager(replica: OccurrenceReplica(records: [template] + children), now: { Date(timeIntervalSince1970: 100) })
        let preview = try await manager.previewSeriesTransition(id: parent, draft: TaskSeriesTransitionDraft(effectiveDate: Date(timeIntervalSince1970: 100), firstDue: #require(formatter.date(from: rawFirst)), recurrence: rule, generatorTimeZone: zone))
        #expect(preview.moved.compactMap(\.deadline).map(formatter.string(from:)) == expected)
    }
}

@Test func transitionRequiresTheOldGeneratorHorizonAndRejectsStalePreview() async throws {
    let parent = UUID(), child = UUID()
    let template = TaskRecord(id: parent, attributes: ["status": "recurring", "due": "100", "recur": "daily", "mask": "-", "description": "Old"])
    let occurrence = TaskRecord(id: child, attributes: ["status": "pending", "parent": parent.uuidString, "imask": "0", "due": "100"])
    let replica = OccurrenceReplica(records: [template, occurrence])
    let manager = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 1000) })
    await #expect(throws: (any Error).self) {
        try await manager.previewSeriesTransition(id: parent, draft: TaskSeriesTransitionDraft(effectiveDate: Date(timeIntervalSince1970: 200000), firstDue: Date(timeIntervalSince1970: 300000), recurrence: "monthly", generatorTimeZone: "UTC"))
    }
    #expect(await replica.batches == 0)
    let preview = try await manager.previewSeriesTransition(id: parent, draft: TaskSeriesTransitionDraft(effectiveDate: Date(timeIntervalSince1970: 1000), firstDue: Date(timeIntervalSince1970: 2000), recurrence: "daily", generatorTimeZone: "UTC"))
    _ = try await replica.updateAtomically([TaskAtomicUpdate(id: child, expected: occurrence.attributes, changes: ["due": "2000"])])
    await #expect(throws: (any Error).self) { try await manager.applySeriesTransition(preview) }
    #expect(try await manager.task(id: parent) == template)
    #expect(try await manager.tasks().count == 2)
}

@Test func transitionRejectsUnprovenClockAmbiguitiesInvalidOffsetsAndIncompatibleUntil() async throws {
    let formatter = ISO8601DateFormatter()
    let parent = UUID()
    let template = TaskRecord(id: parent, attributes: ["status": "recurring", "due": "200", "recur": "weekly", "mask": "---"])
    let children = (0..<3).map { TaskRecord(id: UUID(), attributes: ["status": "pending", "parent": parent.uuidString, "imask": String($0), "due": String(200 + $0)]) }
    let replica = OccurrenceReplica(records: [template] + children)
    let manager = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 100) })
    for (first, rule) in [("2094-02-28T01:30:00Z", "monthly"), ("2093-10-31T01:30:00Z", "yearly")] {
        await #expect(throws: TaskSeriesTransitionError.ambiguousCalendarDate) {
            try await manager.previewSeriesTransition(id: parent, draft: TaskSeriesTransitionDraft(effectiveDate: Date(timeIntervalSince1970: 100), firstDue: #require(formatter.date(from: first)), recurrence: rule, generatorTimeZone: "Europe/Paris"))
        }
    }
    let first = try #require(formatter.date(from: "2094-03-31T09:00:00Z"))
    for draft in [TaskSeriesTransitionDraft(effectiveDate: Date(timeIntervalSince1970: 100), firstDue: first, recurrence: "monthly", generatorTimeZone: "Invalid/Zone"), TaskSeriesTransitionDraft(effectiveDate: Date(timeIntervalSince1970: 100), firstDue: first, recurrence: "monthly", generatorTimeZone: "UTC", planned: .set(.max)), TaskSeriesTransitionDraft(effectiveDate: Date(timeIntervalSince1970: 100), firstDue: first, recurrence: "monthly", generatorTimeZone: "UTC", until: first.addingTimeInterval(86400))] {
        await #expect(throws: (any Error).self) { try await manager.previewSeriesTransition(id: parent, draft: draft) }
    }
    #expect(await replica.batches == 0)
    #expect(try await manager.tasks().count == 4)
}

@Test func retiredTemplatesRemainRecognizedWithoutJoiningNormalPendingViews() {
    let retired = TaskRecord(id: UUID(), attributes: ["status": "deleted", "recur": "monthly", "due": "200", "mask": "+X", "rtype": "periodic"])
    #expect(retired.isRetiredRecurringTemplate)
    #expect(retired.recurrenceInspection?.kind == .template)
    #expect(retired.recurrenceInspection?.issues.isEmpty == true)
    #expect(!TaskQuery.unfinished.includes(retired))
    #expect(!retired.canEdit && !retired.canComplete)
}
