import Foundation

public struct RecurringTaskDraft: Sendable {
    public var task: TaskDraft
    public var firstDue: Date?
    public var recurrence: String

    public init(task: TaskDraft = TaskDraft(), firstDue: Date? = nil, recurrence: String = "weekly") {
        self.task = task
        self.firstDue = firstDue
        self.recurrence = recurrence
    }
}

public enum TaskRecurrenceError: Error, Equatable, LocalizedError, Sendable {
    case invalidFirstDue
    case invalidRule(String)
    case reservedAttribute(String)
    case invalidDateAttribute(String)

    public var errorDescription: String? {
        switch self {
        case .invalidFirstDue: "Choose a first due date after the start of 1970 that leaves room for the recurrence period."
        case .invalidRule: "Enter a positive Taskwarrior recurrence such as daily, weekly, monthly, or 2weeks. Calendar-month and quarter quantities must be whole numbers."
        case .invalidDateAttribute(let key): "The \(key) field must contain valid Unix seconds for external recurrence generation."
        case .reservedAttribute(let key): "The \(key) field is managed by recurring-template creation."
        }
    }
}

public struct TaskRecurrenceRule: Equatable, Sendable {
    public let rawValue: String

    public init(_ value: String) throws {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let duration = TaskwarriorDuration(raw, allowRawSeconds: false), duration.seconds > 0 else { throw TaskRecurrenceError.invalidRule(value) }
        if raw.first?.isNumber == true, raw.hasSuffix("m") || raw.hasSuffix("q") {
            guard TaskwarriorDuration.captures(#"^0*[1-9][0-9]*[mq]$"#, raw) != nil else { throw TaskRecurrenceError.invalidRule(value) }
        }
        let months = TaskwarriorDuration.captures(#"^(?:P)?([0-9]+)([mqM])$"#, raw)
        if let months {
            guard let quantity = Int(months[1]), quantity > 0, quantity <= (months[2] == "q" ? 40000 : 120000) else { throw TaskRecurrenceError.invalidRule(value) }
        } else if !["monthly", "bimonthly", "quarterly", "semiannual", "annual", "yearly", "biannual", "biyearly", "P1Y", "P2Y", "weekdays"].contains(raw), duration.seconds > Int32.max {
            throw TaskRecurrenceError.invalidRule(value)
        }
        rawValue = raw
    }

    func supportsFirstDue(_ instant: TimeInterval) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month], from: Date(timeIntervalSince1970: instant))
        guard let year = components.year, let month = components.month, (1970...9999).contains(year) else { return false }
        let namedMonths = ["monthly": 1, "bimonthly": 2, "quarterly": 3, "semiannual": 6]
        if let step = namedMonths[rawValue] { return step <= (9999 - year) * 12 + 12 - month }
        if let values = TaskwarriorDuration.captures(#"^(?:P)?([0-9]+)([mqM])$"#, rawValue), let quantity = Int(values[1]) {
            return quantity * (values[2] == "q" ? 3 : 1) <= (9999 - year) * 12 + 12 - month
        }
        if ["annual", "yearly", "P1Y"].contains(rawValue) { return year < 9999 }
        if ["biannual", "biyearly", "P2Y"].contains(rawValue) { return year < 9998 }
        let step = rawValue == "weekdays" ? Int64(259200) : TaskwarriorDuration(rawValue, allowRawSeconds: false)?.seconds ?? 0
        return instant + Double(step) <= 253402300799
    }
}

extension TaskManager {
    public func createRecurringTemplate(_ draft: RecurringTaskDraft) async throws -> TaskRecord {
        let lease = try await beginMutation()
        defer { endMutation(lease) }
        let description = draft.task.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else { throw TaskManagementError.emptyDescription }
        guard let due = draft.firstDue?.timeIntervalSince1970, due.isFinite, due > 0, due <= 253402300799, Int(due) != 0 else { throw TaskRecurrenceError.invalidFirstDue }
        let rule = try TaskRecurrenceRule(draft.recurrence)
        guard rule.supportsFirstDue(due) else { throw TaskRecurrenceError.invalidFirstDue }
        let reserved = ["uuid", "id", "status", "recur", "rtype", "mask", "imask", "parent", "template", "last", "end", "entry", "modified"]
        if let key = reserved.first(where: { draft.task.attributes[$0] != nil }) { throw TaskRecurrenceError.reservedAttribute(key) }
        for key in ["scheduled", "wait", "until"] {
            if let raw = draft.task.attributes[key] {
                guard let value = Int64(raw), value > 0, value <= 253402300799 else { throw TaskRecurrenceError.invalidDateAttribute(key) }
            }
        }
        var attributes = try TaskOrganization.normalizedAttributes(draft.task.attributes)
        let typed = try await normalizedUserAttributes(attributes.mapValues { Optional($0) })
        attributes = [:]
        for (name, value) in typed { if let value { attributes[name] = value } }
        let timestamp = String(Int(now().timeIntervalSince1970))
        attributes["description"] = description
        attributes["status"] = "recurring"
        attributes["due"] = String(Int(due))
        attributes["recur"] = rule.rawValue
        attributes["rtype"] = "periodic"
        attributes["entry"] = timestamp
        attributes["modified"] = timestamp
        let saved = try await replica.create(id: UUID(), attributes: attributes)
        localChangeWasCommitted()
        return saved
    }

    public func recurringTemplates() async throws -> [TaskRecord] {
        try await tasks().filter { $0.status == "recurring" && $0.attributes["parent"] == nil }
    }
}
