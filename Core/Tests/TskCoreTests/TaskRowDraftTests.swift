import Foundation
import Testing
@testable import TskCore

@Test func rowNotesSaveWithVisibleEditsAndRetainTimestampIdentity() async throws {
    let manager = TaskManager(replica: TestReplica(), now: { Date(timeIntervalSince1970: 1792144800) })
    let original = try await manager.create(TaskDraft(description: "Original", attributes: ["annotation_01": "Edit me", "annotation_2": "Clear me", "annotation_1792144800": "Keep me", "opaque": "retain"]))
    var draft = TaskRowDraft(task: original)
    draft.taskDraft.attributes["annotation_01"] = "Edited inline\nSecond line"
    draft.taskDraft.attributes["annotation_2"] = ""
    draft.noteInput = "New inline note"
    draft.taskDraft.description = " "
    await #expect(throws: TaskManagementError.emptyDescription) { try await manager.updateRow(draft) }
    #expect(try await manager.task(id: original.id) == original)
    draft.taskDraft.description = "Revised"
    draft.taskDraft.project = "Release"
    let saved = try await manager.updateRow(draft)
    #expect(saved.description == "Revised")
    #expect(saved.project == "Release")
    #expect(saved.attributes["annotation_01"] == "Edited inline\nSecond line")
    #expect(saved.attributes["annotation_2"] == nil)
    #expect(saved.attributes["annotation_1792144800"] == "Keep me")
    #expect(saved.attributes["annotation_1792144801"] == "New inline note")
    #expect(saved.attributes["opaque"] == "retain")
}

@Test func supportingMutationsPreserveUnsavedRowEditsAndFreshHiddenValues() throws {
    let id = UUID()
    let original = TaskRecord(id: id, attributes: ["description": "Original", "status": "pending", "project": "Old", "opaque": "retain", "tag_old": "x", "tag_keep": "original", "annotation_10": "Original note"])
    var draft = TaskRowDraft(task: original)
    draft.taskDraft.description = "Unsaved title"
    draft.taskDraft.project = "New"
    draft.taskDraft.removeTag("old")
    try draft.taskDraft.addTag("next")
    draft.tagInput = "pending"
    draft.taskDraft.attributes["annotation_10"] = "Unsaved note"
    draft.noteInput = "Unsaved new note"
    let annotated = TaskRecord(id: id, attributes: ["description": "Original", "status": "pending", "project": "Old", "annotation_1792144800": "Supporting note", "opaque": "updated", "start": "1792144800", "tag_old": "x", "tag_keep": "updated", "tag_remote": "x", "annotation_10": "Original note"])
    draft.rebase(on: annotated)
    #expect(draft.original == annotated)
    #expect(draft.taskDraft.description == "Unsaved title")
    #expect(draft.taskDraft.attributes["annotation_1792144800"] == "Supporting note")
    #expect(draft.taskDraft.attributes["opaque"] == "updated")
    #expect(draft.taskDraft.attributes["start"] == "1792144800")
    #expect(draft.taskDraft.tags == ["keep", "next", "remote"])
    #expect(draft.taskDraft.attributes["tag_keep"] == "updated")
    #expect(draft.tagInput == "pending")
    #expect(draft.taskDraft.attributes["annotation_10"] == "Unsaved note")
    #expect(draft.noteInput == "Unsaved new note")
    #expect(try draft.changes() == ["description": "Unsaved title", "project": "New", "tag_old": nil, "tag_next": "", "tag_pending": ""])
}

@Test func rowPlanningChangesOnlyScheduledAndPreservesHiddenValues() throws {
    let task = TaskRecord(id: UUID(), attributes: ["description": "Ship", "status": "pending", "due": "1792238400", "wait": "unrecognized", "opaque": "retain"])
    var draft = TaskRowDraft(task: task)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    draft.plan(.tomorrow, now: Date(timeIntervalSince1970: 1792144800), calendar: calendar)
    let changes = try draft.changes()
    #expect(changes == ["scheduled": "1792195200"])
    #expect(draft.taskDraft.attributes["due"] == "1792238400")
    #expect(draft.taskDraft.attributes["wait"] == "unrecognized")
    draft.plan(.remove, now: Date(), calendar: calendar)
    #expect(try draft.changes().isEmpty)
}

@Test func rowDraftValidatesTitleAndSavesOnlyItsVisibleFields() async throws {
    let manager = TaskManager(replica: TestReplica())
    let task = try await manager.create(TaskDraft(description: "Original", attributes: ["project": "Release", "due": "1792238400", "wait": "unknown", "opaque": "retain"]))
    var draft = TaskRowDraft(task: task)
    draft.taskDraft.description = " \n "
    #expect(throws: TaskManagementError.emptyDescription) { try draft.changes() }
    #expect(try await manager.task(id: task.id) == task)
    draft.taskDraft.description = "  Revised  "
    draft.taskDraft.deadline = nil
    draft.taskDraft.attributes["opaque"] = "Accidental hidden edit"
    let saved = try await manager.update(id: task.id, changes: draft.changes())
    #expect(saved.description == "Revised")
    #expect(saved.attributes["due"] == nil)
    #expect(saved.attributes["wait"] == "unknown")
    #expect(saved.attributes["project"] == "Release")
    #expect(saved.attributes["opaque"] == "retain")
}

@Test func failedRowPersistenceLeavesStoredTaskAndEditableDraftIntact() async throws {
    let task = TaskRecord(id: UUID(), attributes: ["description": "Original", "status": "pending", "opaque": "retain"])
    let manager = TaskManager(replica: RowUnwritableReplica(task: task))
    var draft = TaskRowDraft(task: task)
    draft.taskDraft.description = "Unsaved title"
    await #expect(throws: TaskManagementError.storage("Read-only disk")) {
        try await manager.update(id: task.id, changes: draft.changes())
    }
    #expect(try await manager.task(id: task.id) == task)
    #expect(draft.taskDraft.description == "Unsaved title")
    #expect(try draft.changes() == ["description": "Unsaved title"])
}

private struct RowUnwritableReplica: TaskReplica {
    let task: TaskRecord
    func tasks() async throws -> [TaskRecord] { [task] }
    func create(id: UUID, attributes: TaskAttributes) async throws -> TaskRecord { throw TaskManagementError.storage("Read-only disk") }
    func update(id: UUID, changes: TaskAttributePatch) async throws -> TaskRecord { throw TaskManagementError.storage("Read-only disk") }
}

@Test func rowDraftKeepsOccurrenceScopeAndRefusesRecurringTemplates() async throws {
    let parent = UUID(), child = UUID(), siblingID = UUID()
    let template = TaskRecord(id: parent, attributes: ["description": "Series", "status": "recurring", "recur": "daily", "due": "2000000000", "mask": "--"])
    let occurrence = TaskRecord(id: child, attributes: ["description": "First", "status": "pending", "parent": parent.uuidString, "imask": "0"])
    let sibling = TaskRecord(id: siblingID, attributes: ["description": "Second", "status": "pending", "parent": parent.uuidString, "imask": "1"])
    let manager = TaskManager(replica: OccurrenceReplica(records: [template, occurrence, sibling]))
    var draft = TaskRowDraft(task: occurrence)
    draft.taskDraft.description = "Only this occurrence"
    draft.taskDraft.project = "Series.Next"
    draft.taskDraft.priority = "L"
    try draft.taskDraft.addTag("next")
    let saved = try await manager.update(id: occurrence.id, changes: draft.changes())
    #expect(saved.description == "Only this occurrence")
    #expect(saved.project == "Series.Next")
    #expect(saved.priority == "L")
    #expect(saved.tags == ["next"])
    #expect(saved.attributes["parent"] == occurrence.attributes["parent"])
    #expect(try await manager.task(id: sibling.id) == sibling)
    #expect(try await manager.task(id: template.id) == template)
    #expect(throws: TaskManagementError.unsupportedTaskKind) { try TaskRowDraft(task: template).changes() }
}

@Test func chosenScheduledTimestampSurvivesDSTWithoutChangingDeadline() throws {
    var draft = TaskRowDraft(task: TaskRecord(id: UUID(), attributes: ["description": "Plan", "status": "pending", "due": "1806271199"]))
    draft.chooseScheduledDate(Date(timeIntervalSince1970: 1806235200))
    #expect(try draft.changes() == ["scheduled": "1806235200"])
    #expect(draft.taskDraft.attributes["due"] == "1806271199")
}

@Test func openingAndClosingARowDoesNotNormalizeAnUntouchedStoredTitle() throws {
    let task = TaskRecord(id: UUID(), attributes: ["description": "  Imported title  ", "status": "pending", "scheduled": "unknown", "opaque": "retain"])
    let draft = TaskRowDraft(task: task)
    #expect(try draft.changes().isEmpty)
}

@Test func rowOrganizationEditsPersistWithoutChangingIndependentDatesOrHiddenFields() async throws {
    let manager = TaskManager(replica: TestReplica())
    let task = try await manager.create(TaskDraft(description: "Release", attributes: ["project": "Old", "priority": "M", "scheduled": "1792231200", "due": "1792238400", "wait": "unknown", "opaque": "retain"]))
    var draft = TaskRowDraft(task: task)
    draft.taskDraft.project = "New.Project"
    draft.taskDraft.priority = "H"
    let saved = try await manager.update(id: task.id, changes: draft.changes())
    #expect(saved.project == "New.Project")
    #expect(saved.priority == "H")
    #expect(saved.attributes["scheduled"] == "1792231200")
    #expect(saved.attributes["due"] == "1792238400")
    #expect(saved.attributes["wait"] == "unknown")
    #expect(saved.attributes["opaque"] == "retain")
    draft.taskDraft.project = ""
    draft.taskDraft.priority = ""
    #expect(try draft.changes()["project"] == .some(nil))
    #expect(try draft.changes()["priority"] == .some(nil))
}

@Test func rowTagEditsPersistAndClearWithoutTouchingOtherAttributes() async throws {
    let replica = TestReplica()
    let task = try await replica.create(id: UUID(), attributes: ["description": "Organize", "status": "pending", "tag_old": "x", "tag_keep": "original", "tags": "legacy", "priority": "custom", "wait": "malformed", "opaque": "retain"])
    let manager = TaskManager(replica: replica)
    var draft = TaskRowDraft(task: task)
    draft.taskDraft.removeTag("old")
    try draft.taskDraft.addTag("next")
    #expect(try draft.changes() == ["tag_old": nil, "tag_next": ""])
    let saved = try await manager.update(id: task.id, changes: draft.changes())
    #expect(saved.tags == ["keep", "next"])
    #expect(saved.attributes["tag_keep"] == "original")
    #expect(saved.attributes["tags"] == "keep,next")
    #expect(saved.priority == "custom")
    #expect(saved.attributes["wait"] == "malformed")
    #expect(saved.attributes["opaque"] == "retain")
    var cleared = TaskRowDraft(task: saved)
    cleared.taskDraft.removeTag("keep")
    cleared.taskDraft.removeTag("next")
    let reopened = try await manager.update(id: task.id, changes: cleared.changes())
    #expect(reopened.tags.isEmpty)
    #expect(reopened.attributes["tags"] == nil)
}

@Test func unfinishedRowTagInputValidatesOnCollapseAndSurvivesFailure() async throws {
    let task = TaskRecord(id: UUID(), attributes: ["description": "Organize", "status": "pending", "tag_keep": "x"])
    var draft = TaskRowDraft(task: task)
    draft.tagInput = "bad tag"
    #expect(throws: TaskManagementError.invalidTag("bad tag")) { try draft.changes() }
    #expect(draft.tagInput == "bad tag")
    #expect(draft.taskDraft.tags == ["keep"])
    draft.tagInput = "next"
    let manager = TaskManager(replica: RowUnwritableReplica(task: task))
    await #expect(throws: TaskManagementError.storage("Read-only disk")) {
        try await manager.update(id: task.id, changes: draft.changes())
    }
    #expect(draft.tagInput == "next")
    #expect(try draft.changes() == ["tag_next": ""])
    try draft.addTagInput()
    #expect(draft.tagInput.isEmpty)
    #expect(draft.taskDraft.tags == ["keep", "next"])
}

@Test func rowTagEditingPreservesByteDistinctNamesAndUntouchedMalformedValues() throws {
    let task = TaskRecord(id: UUID(), attributes: ["description": "Imported", "status": "pending", "tag_é": "composed", "tag_e\u{301}": "decomposed", "tag_BAD": "malformed", "tags": "legacy", "priority": "custom"])
    var draft = TaskRowDraft(task: task)
    #expect(try draft.changes().isEmpty)
    draft.taskDraft.removeTag("é")
    #expect(try draft.changes() == ["tag_é": nil])
    #expect(draft.taskDraft.attributes["tag_e\u{301}"] == "decomposed")
    #expect(draft.taskDraft.attributes["tag_BAD"] == "malformed")
}

@Test func scheduledDayShortcutsKeepTimeAcrossDSTAndOtherDatesIndependent() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    let parser = ISO8601DateFormatter()
    let original = TaskRecord(id: UUID(), attributes: ["description": "Ship", "status": "pending", "scheduled": "1806149700", "due": "1806271199", "wait": "1806357600"])
    var draft = TaskRowDraft(task: original)
    draft.plan(.tomorrow, now: try #require(parser.date(from: "2027-03-27T10:00:00Z")), calendar: calendar)
    #expect(try draft.changes() == ["scheduled": "1806232500"])
}

@Test(arguments: ["1792195200", "1806235200", "1792888200", "1792891800"])
func reopeningAndEditingOtherFieldsPreservesImportedScheduledTimestamp(timestamp: String) async throws {
    let manager = TaskManager(replica: TestReplica())
    let original = try await manager.create(TaskDraft(description: "Imported", attributes: ["scheduled": timestamp, "due": "1806271199", "wait": "1806357600", "opaque": "retain"]))
    var draft = TaskRowDraft(task: original)
    #expect(try draft.changes().isEmpty)
    draft.taskDraft.description = "Revised"
    let saved = try await manager.update(id: original.id, changes: draft.changes())
    let reopened = TaskRowDraft(task: try await manager.task(id: saved.id))
    #expect(reopened.taskDraft.attributes["scheduled"] == timestamp)
    #expect(reopened.taskDraft.attributes["due"] == "1806271199")
    #expect(reopened.taskDraft.attributes["wait"] == "1806357600")
    #expect(try reopened.changes().isEmpty)
}
