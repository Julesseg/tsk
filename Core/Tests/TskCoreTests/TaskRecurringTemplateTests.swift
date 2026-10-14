import Foundation
import Testing
import TskCore

@Test func creatingARecurringTemplateInitializesCompatibleDataWithoutGeneratingOccurrences() async throws {
    let replica = TestReplica()
    let manager = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 1792144800) })
    let draft = RecurringTaskDraft(task: TaskDraft(description: " Weekly review ", attributes: ["project": "Work", "tag_review": "", "opaque": "retain"]), firstDue: Date(timeIntervalSince1970: 1792224000), recurrence: "weekly")
    let template = try await manager.createRecurringTemplate(draft)
    #expect(template.description == "Weekly review")
    #expect(template.status == "recurring")
    #expect(template.attributes["due"] == "1792224000")
    #expect(template.attributes["recur"] == "weekly")
    #expect(template.attributes["rtype"] == "periodic")
    #expect(template.attributes["entry"] == "1792144800")
    #expect(template.attributes["modified"] == "1792144800")
    #expect(template.attributes["project"] == "Work")
    #expect(template.attributes["tag_review"] != nil)
    #expect(template.attributes["opaque"] == "retain")
    for key in ["mask", "parent", "imask", "end"] { #expect(template.attributes[key] == nil) }
    #expect(try await manager.recurringTemplates() == [template])
    #expect(try await manager.tasks() == [template])
    #expect(try await manager.tasks(query: .unfinished).isEmpty)
    await #expect(throws: TaskManagementError.unsupportedTaskKind) { try await manager.complete(id: template.id) }
    await #expect(throws: TaskManagementError.unsupportedTaskKind) { try await manager.update(id: template.id, changes: ["description": "Accidental ordinary edit"]) }
}

@Test func recurrenceValidationRejectsUnsafeRulesAndDatesBeforeAnyRecordIsCommitted() async throws {
    let manager = TaskManager(replica: TestReplica())
    for date in [nil, Date(timeIntervalSince1970: -1), Date(timeIntervalSince1970: 0), Date(timeIntervalSince1970: 253402300799), Date(timeIntervalSince1970: .nan), Date(timeIntervalSince1970: .infinity), Date(timeIntervalSince1970: 253402300800)] {
        let draft = RecurringTaskDraft(task: TaskDraft(description: "Invalid anchor"), firstDue: date)
        await #expect(throws: TaskRecurrenceError.invalidFirstDue) { try await manager.createRecurringTemplate(draft) }
    }
    for rule in ["", "hourly", "0d", "-1week", "PT0S", "P0M", "0.1s", "1.5m", "0.5q", "P99999999M", "100000years", "P1.5D", "weekly trailing", "60"] {
        let draft = RecurringTaskDraft(task: TaskDraft(description: "Invalid rule"), firstDue: Date(timeIntervalSince1970: 1792224000), recurrence: rule)
        await #expect(throws: (any Error).self) { try await manager.createRecurringTemplate(draft) }
    }
    for key in ["mask", "parent", "imask", "status", "rtype", "template", "last", "entry", "modified", "end"] {
        let draft = RecurringTaskDraft(task: TaskDraft(description: "Bad initialization", attributes: TaskAttributes([(key, "injected")])), firstDue: Date(timeIntervalSince1970: 1792224000))
        await #expect(throws: TaskRecurrenceError.reservedAttribute(key)) { try await manager.createRecurringTemplate(draft) }
    }
    #expect(try await manager.tasks().isEmpty)
}

@Test func recurrenceAuthoringPreservesTheExactRuleInsteadOfReducingCalendarRulesToSeconds() async throws {
    let manager = TaskManager(replica: TestReplica())
    let rules = ["daily", "weekdays", "weekly", "2weeks", "monthly", "1m", "01m", "2m", "P1M", "P2M", "P3M", "quarterly", "2q", "semiannual", "yearly", "P1Y", "2y", "biannual", "1h", "P1DT30M", "P2W", "1.5hours"]
    for rule in rules {
        let record = try await manager.createRecurringTemplate(RecurringTaskDraft(task: TaskDraft(description: rule), firstDue: Date(timeIntervalSince1970: 1792224000), recurrence: rule))
        #expect(record.attributes["recur"] == rule)
        #expect(record.attributes["mask"] == nil)
    }
    #expect(try await manager.tasks().count == rules.count)
}

@Test func recurringInspectionDistinguishesTemplatesAndOccurrencesWithoutUnlockingMutations() async throws {
    let replica = TestReplica()
    let manager = TaskManager(replica: replica)
    let template = try await manager.createRecurringTemplate(RecurringTaskDraft(task: TaskDraft(description: "Inspect series"), firstDue: Date(timeIntervalSince1970: 1792224000)))
    let child = try await replica.create(id: UUID(), attributes: ["description": "Generated review", "status": "pending", "parent": template.id.uuidString.lowercased(), "imask": "0", "recur": "weekly", "due": "1792224000", "opaque": "preserve"])
    #expect(template.recurrenceInspection?.kind == .template)
    #expect(template.recurrenceInspection?.issues.isEmpty == true)
    #expect(child.recurrenceInspection?.kind == .occurrence)
    #expect(child.recurrenceInspection?.parentID == template.id)
    #expect(child.recurrenceInspection?.index == 0)
    #expect(!child.canEdit && !child.canComplete)
    #expect(try await manager.tasks(query: .unfinished) == [child])
    for action in ["complete", "edit"] {
        await #expect(throws: TaskManagementError.unsupportedTaskKind) {
            if action == "complete" { _ = try await manager.complete(id: child.id) }
            else { _ = try await manager.update(id: child.id, changes: ["description": "Unsafe mutation"]) }
        }
    }
    let malformed = try await replica.create(id: UUID(), attributes: ["description": "Malformed series data", "status": "pending", "parent": "not-a-uuid", "imask": "-1", "recur": "hourly", "due": "invalid", "opaque": "retain"])
    #expect(malformed.recurrenceInspection?.issues.isEmpty == false)
    #expect(try await manager.task(id: malformed.id) == malformed)
    #expect(!malformed.canEdit)
}
