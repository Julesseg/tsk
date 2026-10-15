import Foundation
import Testing
@testable import TskCore

@Test func oneTimeCopyMapsIncompleteRemindersAndPreservesContentWithoutSourceIdentity() async throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let source = ImportTestSource(items: [
        ReminderSnapshot(listID: "work", title: "Prepare", notes: "  First\nsecond  ", url: "https://example.com/a", priority: 1,
                         start: DateComponents(year: 2026, month: 10, day: 15), due: DateComponents(year: 2026, month: 10, day: 16, hour: 9, minute: 30)),
        ReminderSnapshot(listID: "work", title: "None", priority: 0),
        ReminderSnapshot(listID: "work", title: "Done", isCompleted: true),
        ReminderSnapshot(listID: "other", title: "Unselected")
    ])
    let manager = TaskManager(replica: TestReplica(), now: { Date(timeIntervalSince1970: 1000) }, calendar: calendar)
    let result = try await manager.copyReminders(from: source, mappings: [ReminderListMapping(listID: "work", project: "Office")])
    #expect(result.imported.count == 2)
    let task = try #require(result.imported.first(where: { $0.description == "Prepare" }))
    #expect(task.attributes["project"] == "Office")
    #expect(task.attributes["priority"] == "H")
    #expect(task.attributes["scheduled"] == "1792022400")
    #expect(task.attributes["due"] == "1792143000")
    #expect(task.annotations.map(\.text) == ["  First\nsecond  ", "https://example.com/a"])
    #expect(task.attributes.keys.sorted() == ["annotation_1000", "annotation_1001", "description", "due", "entry", "modified", "priority", "project", "scheduled", "status"])
    let repeated = try await manager.copyReminders(from: source, mappings: [ReminderListMapping(listID: "work", project: "Office")])
    #expect(Set(result.imported.map(\.id)).isDisjoint(with: repeated.imported.map(\.id)))
    #expect(try await manager.tasks().count == 4)
    #expect(source.items.count == 4)
}

actor ImportTestSource: ReminderSource {
    let items: [ReminderSnapshot]
    init(items: [ReminderSnapshot]) { self.items = items }
    func lists() async throws -> [ReminderList] { [ReminderList(id: "work", title: "Work")] }
    func incompleteReminders(in listIDs: [String]) async throws -> [ReminderSnapshot] { items }
}

@Test func reminderPreviewAndCopyExposeUnsupportedRulesInvalidDatesAndPartialStorageFailure() async throws {
    let source = ImportTestSource(items: [
        ReminderSnapshot(listID: "work", title: "Medium", priority: 5),
        ReminderSnapshot(listID: "work", title: "Low", priority: 9),
        ReminderSnapshot(listID: "work", title: "Rule", recurrenceDescription: "weekly with selector"),
        ReminderSnapshot(listID: "work", title: "Invalid date", due: DateComponents(year: 2026, month: 2, day: 30)),
        ReminderSnapshot(listID: "work", title: " "),
        ReminderSnapshot(listID: "work", title: "Bad priority", priority: 10)
    ])
    let replica = ImportFailingReplica()
    let manager = TaskManager(replica: replica)
    let mappings = [ReminderListMapping(listID: "work", project: "")]
    let preview = try await manager.previewReminderImport(from: source, mappings: mappings)
    #expect(preview[0].draft?.attributes["priority"] == "M")
    #expect(preview[1].draft?.attributes["priority"] == "L")
    #expect(preview[2].reason?.contains("weekly with selector") == true)
    #expect(try await manager.tasks().isEmpty)
    let result = try await manager.copyReminders(from: source, mappings: mappings)
    #expect(result.imported.map(\.description) == ["Medium"])
    #expect(result.skipped.count == 4)
    #expect(result.failures.count == 1)
    #expect(result.failures[0].reason?.contains("Disk is full") == true)
    #expect(try await manager.tasks().map(\.id) == result.imported.map(\.id))
}

@Test func reminderAccessFailureNeverCreatesTasksAndLeavesOrdinaryTasksAvailable() async throws {
    let manager = TaskManager(replica: TestReplica())
    let existing = try await manager.create(TaskDraft(description: "Keep ordinary task", attributes: ["opaque": "preserve"]))
    await #expect(throws: (any Error).self) {
        try await manager.copyReminders(from: ImportDeniedSource(), mappings: [ReminderListMapping(listID: "work", project: "Office")])
    }
    #expect(try await manager.tasks() == [existing])
    await #expect(throws: ReminderImportError.noLists) { try await manager.copyReminders(from: ImportDeniedSource(), mappings: []) }
}

private actor ImportFailingReplica: TaskReplica {
    var records: [TaskRecord] = []
    func tasks() -> [TaskRecord] { records }
    func create(id: UUID, attributes: TaskAttributes) throws -> TaskRecord {
        guard records.isEmpty else { throw TaskManagementError.storage("Disk is full") }
        let record = TaskRecord(id: id, attributes: attributes); records.append(record); return record
    }
    func update(id: UUID, changes: TaskAttributePatch) throws -> TaskRecord { throw TaskManagementError.storage("Disk is full") }
}

private struct ImportDeniedSource: ReminderSource {
    func lists() async throws -> [ReminderList] { throw CocoaError(.fileReadNoPermission) }
    func incompleteReminders(in listIDs: [String]) async throws -> [ReminderSnapshot] { throw CocoaError(.fileReadNoPermission) }
}

@Test func reminderDateOnlyValuesUseSourceTimezoneAcrossDaylightSavingWithoutMergingDates() async throws {
    var sourceCalendar = Calendar(identifier: .gregorian)
    sourceCalendar.timeZone = TimeZone(identifier: "America/New_York")!
    let source = ImportTestSource(items: [ReminderSnapshot(listID: "work", title: "DST dates",
        start: DateComponents(calendar: sourceCalendar, year: 2026, month: 3, day: 8),
        due: DateComponents(calendar: sourceCalendar, year: 2026, month: 3, day: 9))])
    let manager = TaskManager(replica: TestReplica())
    let result = try await manager.copyReminders(from: source, mappings: [ReminderListMapping(listID: "work", project: "")])
    let task = try #require(result.imported.first)
    #expect(task.attributes["scheduled"] == "1772946000")
    #expect(task.attributes["due"] == "1773028800")
    #expect(task.attributes["project"] == nil)
}
