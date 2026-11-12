import Foundation
import Testing
@testable import TskCore

@Test func completionRejectsDeletedAndMissingTargetsWithoutChangingAnyTask() async throws {
    let replica = TestReplica()
    let deleted = try await replica.create(id: UUID(), attributes: ["description": "Deleted", "status": "deleted", "modified": "20", "start": "10"])
    let manager = TaskManager(replica: replica)
    #expect(try await manager.task(id: deleted.id) == deleted)
    await #expect(throws: TaskManagementError.taskDeleted(deleted.id)) {
        try await manager.task(id: deleted.id, includingDeleted: false)
    }
    do {
        _ = try await manager.complete(id: deleted.id)
        Issue.record("Deleted completion must fail")
    } catch {
        #expect(error.localizedDescription == "This task has been deleted. No tasks were changed.")
        #expect(TaskActionFailureCode(error: error, savedLocally: false).rawValue == "task_deleted")
    }
    let missing = UUID()
    await #expect(throws: TaskManagementError.taskNotFound(missing)) { try await manager.complete(id: missing) }
    #expect(try await manager.tasks() == [deleted])
}

@Test func completionPreservesIndependentDatesAndRepeatedCompletionHistory() async throws {
    let replica = TestReplica()
    let original = try await replica.create(id: UUID(), attributes: ["description": "Complete exactly this", "status": "pending", "project": "Travel", "tag_trip": "", "priority": "H", "scheduled": "200", "due": "300", "wait": "150", "start": "90", "opaque": "café", "annotation_50": "Retain note"])
    let first = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 100) })
    let completed = try await first.complete(id: original.id)
    #expect(completed.id == original.id)
    #expect(completed.status == "completed")
    #expect(completed.attributes["start"] == nil)
    #expect(completed.attributes["end"] == "100")
    #expect(completed.attributes["modified"] == "100")
    for key in ["description", "project", "tag_trip", "priority", "scheduled", "due", "wait", "opaque", "annotation_50"] {
        #expect(completed.attributes[key] == original.attributes[key])
    }
    let later = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 900) })
    #expect(try await later.complete(id: original.id) == completed)
    #expect(try await later.tasks() == [completed])
}

@Test func completeURLRequiresExactlyOneFullUUIDAndValidatesCallbacksBeforeExecution() throws {
    let id = "12345678-1234-1234-1234-123456789ABC"
    let parsed = try TaskActionURL(url: #require(URL(string: "tsk://complete?id=" + id + "&x-success=caller%3A%2F%2Fdone")))
    let expectedID = try #require(UUID(uuidString: id))
    #expect(parsed == .complete(expectedID))
    for query in ["", "id=1", "id=12345678123412341234123456789ABC", "id=" + id + "&id=" + id, "id=" + id + "&description=Other", "id=" + id + "&x-success=tsk%3A%2F%2Fcomplete", "id=" + id + "&x-error=caller%3A%2F%2Ferror&x-error=caller%3A%2F%2Fother"] {
        #expect(throws: (any Error).self) { try TaskActionURL(url: #require(URL(string: "tsk://complete?" + query))) }
    }
    for route in ["tsk://complete/path?id=", "tsk://user@complete?id=", "tsk://complete:42?id="] {
        #expect(throws: (any Error).self) { try TaskActionURL(url: #require(URL(string: route + id))) }
    }
}
