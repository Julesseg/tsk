import Foundation
import Testing
import TskCore

@Test func addingAnnotationsUsesUniqueSecondsAndPreservesAllOtherTaskFields() async throws {
    let manager = TaskManager(replica: TestReplica(), now: { Date(timeIntervalSince1970: 1792144800.9) })
    let original = try await manager.create(TaskDraft(description: "Task description", attributes: ["annotation_1792144800": "Existing note", "annotation_1792144801": "Another note", "opaque": "retain", "due": "1792231200"]))
    let saved = try await manager.addAnnotation(id: original.id, text: "  A new note\nwith another line  ")
    #expect(saved.id == original.id)
    #expect(saved.description == "Task description")
    #expect(saved.attributes["annotation_1792144802"] == "  A new note\nwith another line  ")
    #expect(saved.attributes["annotation_1792144800"] == "Existing note")
    #expect(saved.attributes["annotation_1792144801"] == "Another note")
    #expect(saved.attributes["opaque"] == "retain")
    #expect(saved.attributes["due"] == "1792231200")
    let annotations = try await manager.annotations(id: original.id)
    #expect(annotations.map(\.reference.rawValue) == ["annotation_1792144800", "annotation_1792144801", "annotation_1792144802"])
    #expect(annotations.last?.entry == Date(timeIntervalSince1970: 1792144802))
}

@Test func annotationEditKeepsTimestampAndByteExactUnrelatedEntries() async throws {
    let manager = TaskManager(replica: TestReplica(), now: { Date(timeIntervalSince1970: 1792144800) })
    var attributes: TaskAttributes = ["annotation_100": "Original", "annotation_200": "Other note", "annotation_bad": "Keep malformed", "annotation_\u{301}": "Keep combining prefix", "opaque": "é"]
    attributes["e\u{301}"] = "Decomposed key"
    attributes["é"] = "Composed key"
    let original = try await manager.create(TaskDraft(description: "Unchanged description", attributes: attributes))
    let edited = try await manager.editAnnotation(id: original.id, reference: "annotation_100", text: "\u{65}\u{301}\nEdited note")
    #expect(edited.id == original.id)
    #expect(edited.description == original.description)
    #expect(edited.attributes["annotation_100"]?.utf8.elementsEqual("\u{65}\u{301}\nEdited note".utf8) == true)
    #expect(edited.attributes["annotation_200"] == "Other note")
    #expect(edited.attributes["annotation_bad"] == "Keep malformed")
    #expect(edited.attributes["annotation_\u{301}"] == "Keep combining prefix")
    #expect(edited.attributes["e\u{301}"] == "Decomposed key")
    #expect(edited.attributes["é"] == "Composed key")
    #expect(try await manager.annotations(id: original.id).first?.entry == Date(timeIntervalSince1970: 100))
}

@Test func annotationValidationNeverChangesTaskOrAllowsGenericAnnotationOverwrite() async throws {
    let manager = TaskManager(replica: TestReplica())
    let original = try await manager.create(TaskDraft(description: "Keep", attributes: ["annotation_1": "Note"]))
    await #expect(throws: TaskManagementError.emptyAnnotation) { try await manager.addAnnotation(id: original.id, text: " \n\t ") }
    await #expect(throws: TaskManagementError.emptyAnnotation) { try await manager.editAnnotation(id: original.id, reference: "annotation_1", text: "\n") }
    await #expect(throws: TaskManagementError.annotationNotFound("annotation_2")) { try await manager.editAnnotation(id: original.id, reference: "annotation_2", text: "Not a new note") }
    await #expect(throws: TaskManagementError.annotationNotFound("description")) { try await manager.editAnnotation(id: original.id, reference: "description", text: "Not a description edit") }
    await #expect(throws: TaskManagementError.reservedAttribute("annotation_1")) { try await manager.update(id: original.id, changes: ["annotation_1": "Bypass"]) }
    #expect(try await manager.task(id: original.id) == original)
}

@Test func annotationReferencesWithTheSameParsedTimeStayDistinctAndFailuresRemainFailures() async throws {
    let original = TaskRecord(id: UUID(), attributes: ["description": "Read", "status": "pending", "annotation_01": "Leading zero", "annotation_1": "Canonical", "annotation_bad": "Unrecognized", "annotation_\u{301}": "Unrecognized combining suffix"])
    let replica = TestReplica()
    _ = try await replica.create(id: original.id, attributes: original.attributes)
    let manager = TaskManager(replica: replica)
    let before = try await manager.annotations(id: original.id)
    #expect(before.count == 4)
    #expect(before[0].reference.rawValue == "annotation_01")
    #expect(before[1].reference.rawValue == "annotation_1")
    #expect(before[0].entry == before[1].entry)
    let saved = try await manager.editAnnotation(id: original.id, reference: "annotation_01", text: "Edit only this raw key")
    #expect(saved.attributes["annotation_1"] == "Canonical")
    #expect(saved.attributes["annotation_bad"] == "Unrecognized")
    #expect(saved.annotations.filter { $0.entry == nil }.count == 2)
    let failing = TaskManager(replica: AnnotationUnwritableReplica(task: saved))
    await #expect(throws: TaskManagementError.storage("Read-only disk")) { try await failing.addAnnotation(id: saved.id, text: "Unsaved add") }
    await #expect(throws: TaskManagementError.storage("Read-only disk")) { try await failing.editAnnotation(id: saved.id, reference: "annotation_01", text: "Unsaved edit") }
    #expect(try await failing.task(id: saved.id) == saved)
}

@Test func concurrentAnnotationAddsKeepBothNotesAndUnsupportedTasksRemainReadOnly() async throws {
    let replica = TestReplica()
    let manager = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 1792144800) })
    let task = try await manager.create(TaskDraft(description: "Concurrent"))
    async let first = manager.addAnnotation(id: task.id, text: "One")
    async let second = manager.addAnnotation(id: task.id, text: "Two")
    _ = try await (first, second)
    #expect(Set(try await manager.annotations(id: task.id).map(\.text)) == ["One", "Two"])
    #expect(try await manager.annotations(id: task.id).map(\.entry) == [Date(timeIntervalSince1970: 1792144800), Date(timeIntervalSince1970: 1792144801)])
    let template = try await replica.create(id: UUID(), attributes: ["description": "Template", "status": "recurring", "annotation_1": "Keep"])
    await #expect(throws: TaskManagementError.unsupportedTaskKind) { try await manager.addAnnotation(id: template.id, text: "No") }
    await #expect(throws: TaskManagementError.unsupportedTaskKind) { try await manager.editAnnotation(id: template.id, reference: "annotation_1", text: "No") }
    #expect(try await manager.task(id: template.id) == template)
}

private struct AnnotationUnwritableReplica: TaskReplica {
    let task: TaskRecord
    func tasks() async throws -> [TaskRecord] { [task] }
    func create(id: UUID, attributes: TaskAttributes) async throws -> TaskRecord { throw TaskManagementError.storage("Read-only disk") }
    func update(id: UUID, changes: TaskAttributePatch) async throws -> TaskRecord { throw TaskManagementError.storage("Read-only disk") }
}
