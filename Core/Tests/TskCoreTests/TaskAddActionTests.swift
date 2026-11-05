import Foundation
import Testing
@testable import TskCore

@Test func addActionValidatesAllNamedInputsBeforeSavingAndLeavesOmittedDatesUnset() async throws {
    let manager = TaskManager(replica: TestReplica())
    let input = AddTaskInput(description: "  Train tickets  ", project: "Travel", tags: ["trip", "café"], priority: "H", scheduled: Date(timeIntervalSince1970: 1792224000), deadline: Date(timeIntervalSince1970: 1792314000), waitingUntil: Date(timeIntervalSince1970: 1792137600))
    let saved = try await manager.addTask(input)
    #expect(saved.description == "Train tickets")
    #expect(saved.project == "Travel")
    #expect(Set(saved.tags) == ["trip", "café"])
    #expect(saved.priority == "H")
    #expect(saved.plannedDate == input.scheduled)
    #expect(saved.deadline == input.deadline)
    #expect(saved.waitUntil == input.waitingUntil)
    let plain = try await manager.addTask(AddTaskInput(description: "Plain"))
    #expect(plain.plannedDate == nil && plain.deadline == nil && plain.waitUntil == nil)
    for invalid in [AddTaskInput(description: " "), AddTaskInput(description: "Bad tag", tags: ["two words"]), AddTaskInput(description: "Bad priority", priority: "urgent"), AddTaskInput(description: "Bad date", scheduled: Date(timeIntervalSince1970: .infinity))] {
        await #expect(throws: (any Error).self) { try await manager.addTask(invalid) }
    }
    #expect(try await manager.tasks().count == 2)
}

@Test func addURLUsesEncodedNamedFieldsAndRequiresExplicitTimezones() throws {
    let request = try TaskActionURL(url: #require(URL(string: "tsk://add?description=Caf%C3%A9%20%26%20train%2Bbus&project=Travel&tags=trip&tags=errand&priority=M&scheduled=2026-11-05T10:30:00%2B02:00&deadline=2026-11-06T08:00:00Z&waiting-until=2026-11-04T09:00:00Z")))
    guard case .add(let input) = request else { Issue.record("Expected Add Task"); return }
    #expect(input.description == "Café & train+bus")
    #expect(input.tags == ["trip", "errand"])
    #expect(input.scheduled?.timeIntervalSince1970 == 1793867400)
    for query in ["description=One&description=Two", "description=One&scheduled=2026-11-05", "description=One&scheduled=2026-11-05T10:30:00", "description=One&unknown=value", "description=One&priority=urgent", "description=One&tags=two%20words", "project=Home"] {
        #expect(throws: (any Error).self) { try TaskActionURL(url: #require(URL(string: "tsk://add?" + query))) }
    }
    #expect(throws: (any Error).self) { try TaskActionURL(url: #require(URL(string: "tsk://add/path?description=One"))) }
    #expect(throws: (any Error).self) { try TaskActionURL(url: #require(URL(string: "tsk://open-task?id=1"))) }
    let id = UUID()
    #expect(try TaskActionURL(url: #require(URL(string: "tsk://open-task?id=" + id.uuidString))) == .openTask(id))
}

@Test func actionCallbacksPreserveCallerArgumentsAndReturnRichJSONWithoutTruncation() throws {
    let id = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!
    let record = TaskRecord(id: id, attributes: ["description": "Café & + = ?", "status": "pending", "project": "Travel", "priority": "H", "tag_trip": "", "scheduled": "1793867400"])
    let callbacks = try TaskActionCallbacks(url: #require(URL(string: "tsk://add?description=One&x-success=caller%3A%2F%2Fdone%3Ftoken%3Da%252Bb%26token%3Dsecond&x-error=caller%3A%2F%2Ferror")))
    let callback = try #require(try callbacks.successURL(for: record))
    let items = try #require(URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(items.filter { $0.name == "token" }.map(\.value) == ["a+b", "second"])
    let json = try #require(items.first { $0.name == "result" }?.value)
    let payload = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    #expect(payload["savedLocally"] as? Bool == true)
    let task = try #require(payload["task"] as? [String: Any])
    #expect(task["uuid"] as? String == id.uuidString)
    #expect(task["description"] as? String == "Café & + = ?")
    #expect(task["scheduled"] as? String == "2026-11-05T08:30:00Z")
    #expect(task["deadline"] is NSNull)
    #expect(task["waitingUntil"] is NSNull)
    #expect(task["openTaskURL"] as? String == "tsk://open-task?id=" + id.uuidString)
    var huge = record
    huge.attributes["description"] = String(repeating: "é", count: 5000)
    #expect(throws: TaskActionError.resultTooLarge) { try callbacks.successURL(for: huge) }
    let errorURL = try #require(try callbacks.errorURL(code: "result_too_large", message: TaskActionError.resultTooLarge.localizedDescription, savedTaskID: id))
    #expect(errorURL.absoluteString.contains("result_too_large"))
    let oversizedError = try #require(try callbacks.errorURL(code: "invalid_input", message: String(repeating: "é", count: 5000)))
    #expect(oversizedError.absoluteString.contains("result_too_large"))
    let single = try TaskActionCallbacks(url: #require(URL(string: "tsk://add?x-success=caller%3A%2F%2Fdone")))
    #expect(try single.errorURL(code: "invalid_input", message: "Missing description") != nil)
    let errorOnly = try TaskActionCallbacks(url: #require(URL(string: "tsk://add?x-error=caller%3A%2F%2Ferror")))
    #expect(try errorOnly.successURL(for: record) != nil)
    for value in ["https:missing-host", "javascript:alert(1)", "tsk://add?description=Loop", "file:///tmp/file", "caller://done?result=existing", "caller://done#fragment", "caller://done%ZZ"] {
        var source = URLComponents(string: "tsk://add")!
        source.queryItems = [URLQueryItem(name: "x-success", value: value)]
        #expect(throws: (any Error).self) { try TaskActionCallbacks(url: #require(source.url)) }
    }
}

@Test func addURLRejectsImpossibleDatesAndFailedStorageNeverReportsSuccess() async throws {
    for timestamp in ["2026-02-30T08:00:00Z", "2026-13-01T08:00:00Z", "2026-11-05T25:00:00Z", "2026-11-05T10:00:00+25:00"] {
        var url = URLComponents(string: "tsk://add")!
        url.queryItems = [URLQueryItem(name: "description", value: "Invalid date"), URLQueryItem(name: "scheduled", value: timestamp)]
        #expect(throws: (any Error).self) { try TaskActionURL(url: #require(url.url)) }
    }
    let original = TaskRecord(id: UUID(), attributes: ["description": "Existing", "status": "pending"])
    let manager = TaskManager(replica: AddActionUnwritableReplica(task: original))
    await #expect(throws: (any Error).self) { try await manager.addTask(AddTaskInput(description: "Cannot save")) }
    #expect(try await manager.tasks() == [original])
    #expect(TaskActionFailureCode(error: TaskManagementError.storage("Disk full"), savedLocally: false) == .storageError)
    #expect(TaskActionFailureCode(error: TaskManagementError.taskNotFound(original.id), savedLocally: false) == .taskNotFound)
    #expect(TaskActionFailureCode(error: TaskActionError.navigationFailed("Invalid draft"), savedLocally: false) == .navigationError)
    #expect(TaskActionFailureCode(error: TaskActionError.resultTooLarge, savedLocally: true) == .resultTooLarge)
}

private struct AddActionUnwritableReplica: TaskReplica {
    let task: TaskRecord
    func tasks() async throws -> [TaskRecord] { [task] }
    func create(id: UUID, attributes: TaskAttributes) async throws -> TaskRecord { throw TaskManagementError.storage("Disk full") }
    func update(id: UUID, changes: TaskAttributePatch) async throws -> TaskRecord { throw TaskManagementError.storage("Disk full") }
}
