import Foundation
import Testing
@testable import TskCore

@Test func occurrenceCompletionAtomicallyPreservesSeries() async throws {
    let parent = UUID(), child = UUID(), sibling = UUID()
    let original = TaskRecord(id: parent, attributes: ["status": "recurring", "recur": "daily", "due": "2000000000", "mask": "--", "opaque": "keep"])
    let occurrence = TaskRecord(id: child, attributes: ["status": "pending", "description": "first", "parent": parent.uuidString, "imask": "0", "scheduled": "0", "opaque": "child"])
    let other = TaskRecord(id: sibling, attributes: ["status": "pending", "parent": parent.uuidString, "imask": "1"])
    let replica = OccurrenceReplica(records: [original, occurrence, other])
    let manager = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 100) })
    let edited = try await manager.update(id: child, changes: ["description": "only this occurrence"])
    #expect(edited.attributes["parent"] == parent.uuidString)
    let completed = try await manager.complete(id: child)
    #expect(completed.status == "completed")
    #expect(completed.attributes["end"] == "100")
    #expect(try await manager.dayPage(on: Date(timeIntervalSince1970: 100)) == [completed])
    let records = try await manager.tasks()
    #expect(records.first { $0.id == parent }?.attributes["mask"] == "+-")
    #expect(records.first { $0.id == parent }?.attributes["opaque"] == "keep")
    #expect(records.first { $0.id == sibling } == other)
    #expect(try await manager.complete(id: child) == completed)
    #expect(await replica.batches == 2)
}

@Test func malformedOccurrenceNeverWrites() async throws {
    let parent = UUID(), child = UUID()
    for mask in ["", "?", "+", "--"] {
        let records = [TaskRecord(id: parent, attributes: ["status": "recurring", "mask": mask]), TaskRecord(id: child, attributes: ["status": "pending", "parent": parent.uuidString, "imask": "9"])]
        let replica = OccurrenceReplica(records: records)
        let manager = TaskManager(replica: replica)
        await #expect(throws: (any Error).self) { try await manager.complete(id: child) }
        #expect(try await replica.tasks() == records)
        #expect(await replica.batches == 0)
    }
}

actor OccurrenceReplica: TaskAtomicTransitionReplica {
    var records: [TaskRecord]
    var batches = 0
    private var rejectsNextUpdate = false
    func rejectNextUpdate() { rejectsNextUpdate = true }
    private let allowsSingleWrites: Bool
    init(records: [TaskRecord], allowsSingleWrites: Bool = false) {
        self.records = records
        self.allowsSingleWrites = allowsSingleWrites
    }
    func tasks() -> [TaskRecord] { records }
    func create(id: UUID, attributes: TaskAttributes) throws -> TaskRecord {
        guard allowsSingleWrites else { throw TaskManagementError.storage("Unexpected create") }
        return try commitAtomically(creating: [.init(id: id, attributes: attributes)], updating: [], expecting: records)[0]
    }
    func update(id: UUID, changes: TaskAttributePatch) throws -> TaskRecord {
        guard allowsSingleWrites, let task = records.first(where: { $0.id == id }) else { throw TaskManagementError.storage("Sequential update forbidden") }
        return try updateAtomically([.init(id: id, expected: task.attributes, changes: changes)])[0]
    }
    func commitAtomically(creating: [TaskAtomicCreate], updating updates: [TaskAtomicUpdate], expecting snapshot: [TaskRecord]) throws -> [TaskRecord] {
        guard records.sorted(by: { $0.id.uuidString < $1.id.uuidString }) == snapshot.sorted(by: { $0.id.uuidString < $1.id.uuidString }), creating.allSatisfy({ new in !records.contains { $0.id == new.id } }) else { throw TaskSeriesMetadataError.stalePreview }
        let saved = try updateAtomically(updates)
        let created = creating.map { TaskRecord(id: $0.id, attributes: $0.attributes) }
        records += created
        return created + saved
    }
    func updateAtomically(_ updates: [TaskAtomicUpdate], expecting snapshot: [TaskRecord]) throws -> [TaskRecord] {
        guard records.sorted(by: { $0.id.uuidString < $1.id.uuidString }) == snapshot.sorted(by: { $0.id.uuidString < $1.id.uuidString }) else { throw TaskSeriesMetadataError.stalePreview }
        return try updateAtomically(updates)
    }
    func updateAtomically(_ updates: [TaskAtomicUpdate]) throws -> [TaskRecord] {
        if rejectsNextUpdate { rejectsNextUpdate = false; throw TaskManagementError.storage("Injected atomic storage failure") }
        for update in updates { guard records.first(where: { $0.id == update.id })?.attributes == update.expected else { throw TaskManagementError.storage("Conflict") } }
        batches += 1
        return updates.map { update in
            let index = records.firstIndex { $0.id == update.id }!
            for (key, value) in update.changes { records[index].attributes[key] = value }
            return records[index]
        }
    }
}

@Test func occurrenceWaitEditsKeepTheCompatibleMaskAndReservedLinksIntact() async throws {
    let parent = UUID(), child = UUID()
    let replica = OccurrenceReplica(records: [TaskRecord(id: parent, attributes: ["status": "recurring", "mask": "-"]), TaskRecord(id: child, attributes: ["status": "pending", "description": "Child", "parent": parent.uuidString, "imask": "0", "due": "300"])])
    let manager = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 100) })
    _ = try await manager.update(id: child, changes: ["wait": "200"])
    #expect(try await manager.task(id: parent).attributes["mask"] == "W")
    _ = try await manager.update(id: child, changes: ["due": "500"])
    #expect(try await manager.task(id: parent).attributes["mask"] == "W")
    await #expect(throws: (any Error).self) { try await manager.update(id: child, changes: ["due": nil]) }
    await #expect(throws: TaskManagementError.reservedAttribute("parent")) { try await manager.update(id: child, changes: ["parent": UUID().uuidString]) }
    _ = try await manager.update(id: child, changes: ["wait": nil])
    #expect(try await manager.task(id: parent).attributes["mask"] == "-")
}

@Test func occurrenceIntegrityFailuresPreserveEveryRecord() async throws {
    let parent = UUID(), child = UUID()
    let validParent = TaskRecord(id: parent, attributes: ["status": "recurring", "mask": "-"])
    let validChild = TaskRecord(id: child, attributes: ["status": "pending", "parent": parent.uuidString, "imask": "0", "description": "Child"])
    for (key, value) in [("parent", child.uuidString), ("parent", "missing"), ("imask", "-1"), ("imask", "999999999999999999999999"), ("imask", ""), ("imask", "1")] {
        var invalid = validChild
        invalid.attributes[key] = value
        let replica = OccurrenceReplica(records: [validParent, invalid])
        let manager = TaskManager(replica: replica)
        await #expect(throws: (any Error).self) { try await manager.complete(id: child) }
        #expect(await replica.records == [validParent, invalid])
        #expect(await replica.batches == 0)
    }
    let duplicate = TaskRecord(id: UUID(), attributes: validChild.attributes)
    let replica = OccurrenceReplica(records: [validParent, validChild, duplicate])
    let manager = TaskManager(replica: replica)
    await #expect(throws: (any Error).self) { try await manager.complete(id: child) }
    #expect(await replica.batches == 0)
}

@Test func reopeningAWaitingOccurrenceRestoresItsSeriesMaskAtomically() async throws {
    let parent = UUID(), child = UUID()
    let replica = OccurrenceReplica(records: [
        TaskRecord(id: parent, attributes: ["status": "recurring", "mask": "W-"]),
        TaskRecord(id: child, attributes: ["status": "pending", "parent": parent.uuidString, "imask": "0", "due": "400", "wait": "300"])
    ])
    let manager = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 100) })
    let completed = try await manager.complete(id: child)
    #expect(try await manager.task(id: parent).attributes["mask"] == "+-")
    await replica.rejectNextUpdate()
    await #expect(throws: (any Error).self) { try await manager.reopen(id: child) }
    #expect(try await manager.task(id: child) == completed)
    #expect(try await manager.task(id: parent).attributes["mask"] == "+-")
    let reopened = try await manager.reopen(id: child)
    #expect(reopened.status == "pending" && reopened.attributes["end"] == nil)
    #expect(reopened.attributes["wait"] == "300" && reopened.attributes["due"] == "400")
    #expect(try await manager.task(id: parent).attributes["mask"] == "W-")
}
