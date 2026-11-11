import Foundation
import Testing
@testable import TskCore

@Test func deleteActionSoftDeletesOneTaskAndRepeatsWithoutChangingHistory() async throws {
    let replica = TestReplica()
    let manager = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 100) })
    let original = try await manager.create(TaskDraft(description: "Delete once", attributes: ["opaque": "retain", "annotation_10": "history", "start": "50", "scheduled": "200", "tag_trip": ""]))
    let unrelated = try await manager.create(TaskDraft(description: "Keep"))
    let deleted = try await manager.delete(id: original.id)
    var expected = original
    expected.attributes["status"] = "deleted"
    expected.attributes["end"] = "100"
    expected.attributes["modified"] = "100"
    expected.attributes["start"] = nil
    #expect(deleted == expected)
    let later = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 200) })
    #expect(try await later.delete(id: original.id) == deleted)
    #expect(try await later.task(id: unrelated.id) == unrelated)
    #expect(try await later.findTasks(FindTasksInput(status: .all)) == [unrelated])
    #expect(try await replica.tasks().count == 2)
    await #expect(throws: TaskManagementError.unsupportedTaskKind) { try await later.update(id: original.id, changes: ["description": "Rejected"]) }
    await #expect(throws: TaskManagementError.unsupportedTaskKind) { try await later.complete(id: original.id) }
    await #expect(throws: TaskManagementError.taskNotFound(original.id)) { try await later.openTask(id: original.id) }
    let missing = UUID()
    await #expect(throws: TaskManagementError.taskNotFound(missing)) { try await later.delete(id: missing) }
}

@Test func deleteCompletedTasksPreservesCompletionTimeAndRejectsRecurringTemplatesAndFailedStorage() async throws {
    let replica = TestReplica()
    let completed = try await replica.create(id: UUID(), attributes: ["description": "Done", "status": "completed", "end": "42", "opaque": "keep"])
    let manager = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 100) })
    let deleted = try await manager.delete(id: completed.id)
    #expect(deleted.status == "deleted")
    #expect(deleted.attributes["end"] == "42")
    let template = try await replica.create(id: UUID(), attributes: ["status": "recurring", "recur": "daily", "mask": "-"])
    await #expect(throws: TaskManagementError.unsupportedTaskKind) { try await manager.delete(id: template.id) }
    #expect(try await manager.task(id: template.id) == template)
    let original = TaskRecord(id: UUID(), attributes: ["description": "Unsaved", "status": "pending"])
    let failing = TaskManager(replica: DeleteFailureReplica(record: original))
    await #expect(throws: TaskManagementError.storage("Disk full")) { try await failing.delete(id: original.id) }
    #expect(try await failing.task(id: original.id) == original)
}

@Test func deleteOccurrenceUsesAtomicMaskForPendingWaitingAndCompletedAndRejectsInconsistentState() async throws {
    for (status, mask) in [("pending", "-"), ("pending", "W"), ("completed", "+")] {
        let parent = TaskRecord(id: UUID(), attributes: ["status": "recurring", "mask": mask + "-", "opaque": "parent"])
        let child = TaskRecord(id: UUID(), attributes: ["description": "Occurrence", "status": status, "parent": parent.id.uuidString, "imask": "0", "due": "200", "end": "50"])
        let sibling = TaskRecord(id: UUID(), attributes: ["status": "pending", "parent": parent.id.uuidString, "imask": "1", "due": "300"])
        let replica = OccurrenceReplica(records: [parent, child, sibling])
        let manager = TaskManager(replica: replica)
        let deleted = try await manager.delete(id: child.id)
        #expect(deleted.status == "deleted")
        #expect(deleted.attributes["end"] == "50")
        #expect(try await manager.task(id: parent.id).attributes["mask"] == "X-")
        #expect(try await manager.task(id: sibling.id) == sibling)
        #expect(try await manager.delete(id: child.id) == deleted)
        #expect(await replica.batches == 1)
    }
    let parent = TaskRecord(id: UUID(), attributes: ["status": "recurring", "mask": "+"])
    let child = TaskRecord(id: UUID(), attributes: ["status": "pending", "parent": parent.id.uuidString, "imask": "0"])
    for records in [[parent, child], [child], [parent, child, TaskRecord(id: UUID(), attributes: child.attributes)]] {
        let replica = OccurrenceReplica(records: records)
        await #expect(throws: (any Error).self) { try await TaskManager(replica: replica).delete(id: child.id) }
        #expect(await replica.records == records)
        #expect(await replica.batches == 0)
    }
    let validParent = TaskRecord(id: parent.id, attributes: ["status": "recurring", "mask": "-"])
    let nonAtomic = DeleteFailureReplica(records: [validParent, child])
    await #expect(throws: (any Error).self) { try await TaskManager(replica: nonAtomic).delete(id: child.id) }
}

@Test func deleteURLRequiresExactlyOneFullUUIDAndReturnsSharedRichSavedResult() throws {
    let id = UUID()
    let deleteURL = try #require(URL(string: "tsk://delete?id=" + id.uuidString))
    #expect(try TaskActionURL(url: deleteURL) == .delete(id))
    for query in ["", "id=1", "id=" + id.uuidString + "&id=" + id.uuidString, "id=" + id.uuidString + "&purge=true", "id=" + id.uuidString + "&x-success=tsk%3A%2F%2Fadd"] {
        #expect(throws: (any Error).self) { try TaskActionURL(url: #require(URL(string: "tsk://delete?" + query))) }
    }
    let callbacks = try TaskActionCallbacks(url: #require(URL(string: "tsk://delete?id=\(id.uuidString)&x-success=caller%3A%2F%2Fdone")))
    let record = TaskRecord(id: id, attributes: ["description": "Gone", "status": "deleted", "project": "Travel", "tag_trip": ""])
    let url = try #require(try callbacks.successURL(for: record))
    let result = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "result" }?.value)
    let payload = try #require(try JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any])
    #expect(payload["savedLocally"] as? Bool == true)
    let task = try #require(payload["task"] as? [String: Any])
    #expect(task["uuid"] as? String == id.uuidString)
    #expect(task["status"] as? String == "deleted")
    #expect(task["project"] as? String == "Travel")
}

private struct DeleteFailureReplica: TaskReplica {
    let records: [TaskRecord]
    init(record: TaskRecord) { records = [record] }
    init(records: [TaskRecord]) { self.records = records }
    func tasks() async throws -> [TaskRecord] { records }
    func create(id: UUID, attributes: TaskAttributes) async throws -> TaskRecord { throw TaskManagementError.storage("Disk full") }
    func update(id: UUID, changes: TaskAttributePatch) async throws -> TaskRecord { throw TaskManagementError.storage("Disk full") }
}
