import Foundation
import Testing
@testable import TskCore

let verifiedWeeklyRule = #"[{"calendar":"gregorian","endCount":0,"endDate":null,"firstDayOfWeek":2,"frequency":1,"interval":1,"monthdays":[],"months":[],"positions":[],"weekdays":[],"yeardays":[],"yearweeks":[]}]"#

func currentWeeklyReminder(rule: String = verifiedWeeklyRule, sourceType: Int? = 0, day: Int = 6, completed: Bool = false) -> ReminderSnapshot {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let anchor = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2030, month: 2, day: day, hour: 9, minute: 0, second: 0)
    return ReminderSnapshot(listID: "work", title: "Weekly current anchor", notes: "  Fixture notes\nsecond line  ", url: "https://example.com/reminder", priority: 1, start: anchor, due: anchor, isCompleted: completed, recurrenceDescription: rule, sourceType: sourceType)
}

@Test func verifiedWeeklyReminderCopiesToATemplateAtCurrentIncompleteAnchorWithoutImportingHistory() async throws {
    let source = ImportTestSource(items: [currentWeeklyReminder(), currentWeeklyReminder(day: 1, completed: true)])
    let manager = TaskManager(replica: TestReplica(), now: { Date(timeIntervalSince1970: 1000) })
    let mappings = [ReminderListMapping(listID: "work", project: "Office")]
    let preview = try await manager.previewReminderImport(from: source, mappings: mappings)
    #expect(preview.count == 1)
    #expect(preview.first?.recurrence == "1week")
    let result = try await manager.copyReminders(from: source, mappings: mappings)
    let saved = try #require(result.imported.first)
    #expect(result.skipped.isEmpty && result.failures.isEmpty)
    #expect(saved.status == "recurring")
    #expect(saved.attributes["rtype"] == "periodic")
    #expect(saved.attributes["recur"] == "1week")
    #expect(saved.attributes["due"] == "1896598800")
    #expect(saved.attributes["scheduled"] == "1896598800")
    #expect(saved.attributes["priority"] == "H")
    #expect(saved.attributes["project"] == "Office")
    #expect(saved.annotations.map(\.text) == ["  Fixture notes\nsecond line  ", "https://example.com/reminder"])
    #expect(saved.attributes.keys.sorted() == ["annotation_1000", "annotation_1001", "description", "due", "entry", "modified", "priority", "project", "recur", "rtype", "scheduled", "status"])
    #expect(try await manager.recurringTemplates() == [saved])
    #expect(try await manager.tasks().count == 1)
    #expect(await source.items.count == 2)
}

@Test func unverifiedRecurrenceFieldsAndDateSemanticsStayIntactInBothImportModes() async throws {
    var rules: [String] = []
    let original = try #require(JSONSerialization.jsonObject(with: Data(verifiedWeeklyRule.utf8)) as? [[String: Any]])
    for (key, value) in [("frequency", 0 as Any), ("interval", 2), ("calendar", "buddhist"), ("firstDayOfWeek", 1), ("weekdays", [["day": 4, "ordinal": 0]]), ("monthdays", [1]), ("yeardays", [1]), ("yearweeks", [1]), ("months", [2]), ("positions", [1]), ("endCount", 3), ("endDate", 2000000000), ("unfamiliar", true)] {
        var modified = original; modified[0][key] = value
        rules.append(String(decoding: try JSONSerialization.data(withJSONObject: modified), as: UTF8.self))
    }
    rules.append("unrecognized rule")
    rules.append(String(decoding: try JSONSerialization.data(withJSONObject: original + original), as: UTF8.self))
    var snapshots = rules.map { currentWeeklyReminder(rule: $0) }
    snapshots += [currentWeeklyReminder(sourceType: nil), currentWeeklyReminder(sourceType: 2)]
    let normal = currentWeeklyReminder()
    var independent = try #require(normal.start); independent.day = 7
    snapshots.append(ReminderSnapshot(listID: "work", title: "Independent dates", start: normal.start, due: independent, recurrenceDescription: verifiedWeeklyRule, sourceType: 0))
    for zone in [TimeZone(identifier: "Europe/Paris"), nil] {
        var anchor = try #require(normal.start); anchor.timeZone = zone
        snapshots.append(ReminderSnapshot(listID: "work", title: "Unverified timezone", start: anchor, due: anchor, recurrenceDescription: verifiedWeeklyRule, sourceType: 0))
    }
    var missingClock = try #require(normal.start); missingClock.hour = nil
    snapshots.append(ReminderSnapshot(listID: "work", title: "Date only", start: missingClock, due: missingClock, recurrenceDescription: verifiedWeeklyRule, sourceType: 0))
    var invalidDay = try #require(normal.start); invalidDay.day = 30
    snapshots.append(ReminderSnapshot(listID: "work", title: "Invalid calendar day", start: invalidDay, due: invalidDay, recurrenceDescription: verifiedWeeklyRule, sourceType: 0))
    let source = RecurringMoveTestSource(items: snapshots)
    let manager = TaskManager(replica: TestReplica())
    let mappings = [ReminderListMapping(listID: "work", project: "")]
    let copy = try await manager.copyReminders(from: source, mappings: mappings)
    let move = try await manager.moveReminders(from: source, mappings: mappings)
    #expect(copy.imported.isEmpty && move.imported.isEmpty)
    #expect(copy.skipped.count == snapshots.count && move.skipped.count == snapshots.count)
    #expect(copy.skipped.allSatisfy { $0.reason?.isEmpty == false })
    #expect(await source.removed == 0)
    #expect(try await manager.tasks().isEmpty)
}

actor RecurringMoveTestSource: ReminderMoveSource {
    let items: [ReminderSnapshot]
    var removed = 0
    init(items: [ReminderSnapshot]) { self.items = items }
    func lists() -> [ReminderList] { [ReminderList(id: "work", title: "Work")] }
    func incompleteReminders(in listIDs: [String]) -> [ReminderSnapshot] { items }
    func moveCandidates(in listIDs: [String]) -> [ReminderMoveCandidate] {
        items.map { ReminderMoveCandidate(snapshot: $0, removeSource: { await self.remove() }) }
    }
    func remove() { removed += 1 }
}

@Test func continuousVerifiedRecurrenceIsRemovedOnlyAfterValidDurableTemplateAndCommitFailuresKeepSource() async throws {
    let mappings = [ReminderListMapping(listID: "work", project: "Office")]
    let manager = TaskManager(replica: TestReplica(), reminderImportConfiguration: MoveConfigurationStore(device: UUID()))
    try await manager.configureContinuousReminders(enabled: true, mappings: mappings)
    let source = RecurringMoveTestSource(items: [currentWeeklyReminder()])
    let result = try #require(try await manager.runContinuousReminderImport(from: source))
    #expect(result.imported.first?.status == "recurring")
    #expect(result.removedCount == 1)
    #expect(try await manager.recurringTemplates().count == 1)
    for replica: any TaskReplica in [RecurringUnwritableReplica(), MalformedRecurringReplica(), MalformedRecurringReplica(dropsContent: true)] {
        let failed = TaskManager(replica: replica)
        let kept = RecurringMoveTestSource(items: [currentWeeklyReminder()])
        let failure = try await failed.moveReminders(from: kept, mappings: mappings)
        #expect(failure.stopped)
        #expect(failure.removedCount == 0)
        #expect(await kept.removed == 0)
    }
}

private struct RecurringUnwritableReplica: TaskReplica {
    func tasks() -> [TaskRecord] { [] }
    func create(id: UUID, attributes: TaskAttributes) throws -> TaskRecord { throw TaskManagementError.storage("Actual save failed") }
    func update(id: UUID, changes: TaskAttributePatch) throws -> TaskRecord { throw TaskManagementError.storage("Actual save failed") }
}
private struct MalformedRecurringReplica: TaskReplica {
    var dropsContent = false
    func tasks() -> [TaskRecord] { [] }
    func create(id: UUID, attributes: TaskAttributes) -> TaskRecord {
        var changed = attributes
        if dropsContent { changed.removeValue(forKey: "project") } else { changed["status"] = "pending" }
        return TaskRecord(id: id, attributes: changed)
    }
    func update(id: UUID, changes: TaskAttributePatch) throws -> TaskRecord { throw TaskManagementError.unsupportedTaskKind }
}
