import Foundation

public struct TaskRecurrenceInspection: Sendable {
    public enum Kind: Sendable { case template, occurrence, unrecognized }
    public let kind: Kind
    public let rule: String?
    public let firstDue: Date?
    public let parentID: UUID?
    public let index: Int?
    public let mask: String?
    public let issues: [String]

    public init?(_ task: TaskRecord) {
        guard task.isRecurring else { return nil }
        kind = task.attributes["parent"] != nil ? .occurrence : (task.status == "recurring" || task.isRetiredRecurringTemplate) ? .template : .unrecognized
        rule = task.attributes["recur"]
        firstDue = task.deadline
        parentID = task.attributes["parent"].flatMap(UUID.init(uuidString:))
        index = task.occurrenceIndex
        mask = task.attributes["mask"]
        var issues: [String] = []
        if rule.flatMap({ try? TaskRecurrenceRule($0) }) == nil { issues.append("The saved recurrence rule is missing or unsupported. Its raw value is preserved.") }
        if firstDue == nil || firstDue?.timeIntervalSince1970 == 0 { issues.append("The saved due date is missing or invalid.") }
        if kind == .occurrence, parentID == nil || index == nil { issues.append("This occurrence has an invalid template link or position.") }
        if let mask, !mask.utf8.allSatisfy({ "-+XW".utf8.contains($0) }) { issues.append("The saved recurrence mask contains an unknown state.") }
        if let type = task.attributes["rtype"], type != "periodic" { issues.append("This recurrence type is not supported for authoring.") }
        if kind == .unrecognized { issues.append("These recurrence fields do not identify a supported template or occurrence.") }
        self.issues = issues
    }
}

extension TaskRecord {
    public var recurrenceInspection: TaskRecurrenceInspection? { TaskRecurrenceInspection(self) }
}
