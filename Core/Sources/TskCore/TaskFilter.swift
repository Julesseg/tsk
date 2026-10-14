import Foundation

public enum TaskFilterError: Error, Equatable, LocalizedError, Sendable {
    case syntax(String, byteOffset: Int)
    case unknownAttribute(String)
    case unsupported(String)
    case invalidRegex(String, String)

    public var errorDescription: String? {
        switch self {
        case .syntax(let message, let offset): "Filter at byte \(offset + 1): \(message)"
        case .unknownAttribute(let name): "Unknown filter attribute ‘\(name)’. Define its local schema before filtering it."
        case .unsupported(let message): "Unsupported filter: \(message)"
        case .invalidRegex(let pattern, let message): "Invalid ECMAScript pattern ‘\(pattern)’: \(message)"
        }
    }
}

public enum TaskFilterAttributeType: String, CaseIterable, Codable, Sendable {
    case string, date, numeric, duration, uuid
}

public struct TaskFilterSchema: Sendable {
    var attributes: [UTF8String: TaskFilterAttributeType]
    private static let builtinNames = Set(["description", "project", "status", "uuid", "rtype", "depends", "tags", "mask", "imask", "parent", "recur", "entry", "modified", "start", "end", "due", "scheduled", "wait", "until", "id", "urgency", "last", "template"].map { UTF8String($0) })

    public init(attributes: [(String, TaskFilterAttributeType)] = []) {
        self.attributes = Dictionary(attributes.map { (UTF8String($0.0), $0.1) }, uniquingKeysWith: { _, new in new })
    }

    public func contains(_ name: String) -> Bool {
        attributes[UTF8String(name)] != nil || Self.builtinNames.contains(UTF8String(name)) || ["annotation_", "tag_", "dep_"].contains { name.utf8.starts(with: $0.utf8) }
    }

    public func isUserDefined(_ name: String) -> Bool {
        attributes[UTF8String(name)] != nil && !Self.builtinNames.contains(UTF8String(name))
    }

    public func type(for name: String) -> TaskFilterAttributeType? { attributes[UTF8String(name)] }

    public func adding(_ definitions: [TaskAttributeDefinition]) -> TaskFilterSchema {
        var result = self
        for definition in definitions where !Self.standard.contains(definition.name.rawValue) {
            result.attributes[definition.name] = definition.type
        }
        return result
    }

    public static let standard = TaskFilterSchema(attributes:
        ["description", "project", "priority", "status", "uuid", "rtype", "depends", "tags", "mask", "imask", "parent", "template"].map { ($0, .string) }
        + [("recur", .duration), ("id", .numeric), ("urgency", .numeric)]
        + ["entry", "modified", "start", "end", "due", "scheduled", "wait", "until", "last"].map { ($0, .date) })
}

struct TaskFilterContext: Sendable {
    let tasks: [TaskRecord]
    let now: Date
    let calendar: Calendar
    let schema: TaskFilterSchema
}

struct CompiledTaskFilter: Sendable {
    let root: FilterExpression

    init(_ expression: String, schema: TaskFilterSchema) throws {
        var parser = try FilterParser(expression, schema: schema)
        root = try parser.parse()
    }

    func includes(_ task: TaskRecord, context: TaskFilterContext) throws -> Bool {
        // Taskwarrior 3.5 narrows a plain +ACTIVE query before evaluating its predicates.
        if root.requiresWorkingSet, task.status == "completed" || task.status == "deleted" { return false }
        return try root.includes(task, context: context)
    }

    func nextEvaluation(context: TaskFilterContext) -> Date? { root.nextEvaluation(context: context) }
}

indirect enum FilterExpression: Sendable {
    case all
    case predicate(FilterPredicate)
    case not(FilterExpression)
    case and(FilterExpression, FilterExpression)
    case or(FilterExpression, FilterExpression)
    case xor(FilterExpression, FilterExpression)

    var requiresWorkingSet: Bool {
        guard !hasDisjunction else { return false }
        return hasActiveTag
    }

    private var hasDisjunction: Bool {
        switch self {
        case .or, .xor: true
        case .not(let child): child.hasDisjunction
        case .and(let left, let right): left.hasDisjunction || right.hasDisjunction
        default: false
        }
    }

    private var hasActiveTag: Bool {
        switch self {
        case .predicate(.virtualTag(.active, let required)): required
        case .and(let left, let right): left.hasActiveTag || right.hasActiveTag
        case .not(let child): child.hasActiveTag
        default: false
        }
    }

    func includes(_ task: TaskRecord, context: TaskFilterContext) throws -> Bool {
        switch self {
        case .all: true
        case .predicate(let predicate): try predicate.includes(task, context: context)
        case .not(let expression): try !expression.includes(task, context: context)
        case .and(let left, let right): try left.includes(task, context: context) && right.includes(task, context: context)
        case .or(let left, let right): try left.includes(task, context: context) || right.includes(task, context: context)
        case .xor(let left, let right): try left.includes(task, context: context) != right.includes(task, context: context)
        }
    }
}

extension TaskManager {
    public func tasks(filter expression: String, schema: TaskFilterSchema = .standard) async throws -> [TaskRecord] {
        try await viewSnapshot(filter: expression, schema: schema).tasks
    }

    public func viewSnapshot(filter expression: String, schema: TaskFilterSchema = .standard) async throws -> TaskViewSnapshot {
        let schema = try await effectiveFilterSchema(base: schema)
        let filter = try CompiledTaskFilter(expression, schema: schema)
        let records = try await tasks()
        var filterCalendar = Calendar(identifier: .gregorian)
        filterCalendar.timeZone = calendar.timeZone
        let instant = Date(timeIntervalSince1970: floor(now().timeIntervalSince1970))
        let context = TaskFilterContext(tasks: records, now: instant, calendar: filterCalendar, schema: schema)
        let visible = try records.filter { try filter.includes($0, context: context) }
        return TaskViewSnapshot(tasks: visible, allTasks: records, projects: TaskProjectSelection.names(in: records), nextEvaluation: filter.nextEvaluation(context: context))
    }

    public func validateFilter(_ expression: String, schema: TaskFilterSchema = .standard) async throws {
        _ = try CompiledTaskFilter(expression, schema: await effectiveFilterSchema(base: schema))
    }
}
