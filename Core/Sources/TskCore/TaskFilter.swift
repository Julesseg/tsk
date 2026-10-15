import Foundation

public enum TaskFilterError: Error, Equatable, LocalizedError, Sendable {
    case syntax(String, byteOffset: Int)
    case unknownAttribute(String)
    case unsupported(String)
    case invalidRegex(String, String)
    case invalidStoredValue(UUID, String, TaskFilterAttributeType)
    case evaluation(String)

    public var errorDescription: String? {
        switch self {
        case .evaluation(let message): "Filter evaluation: \(message)"
        case .syntax(let message, let offset): "Filter at byte \(offset + 1): \(message)"
        case .unknownAttribute(let name): "Unknown filter attribute ‘\(name)’. Define its local schema before filtering it."
        case .unsupported(let message): "Unsupported filter: \(message)"
        case .invalidStoredValue(let id, let name, let type): "Task \(id.uuidString) has an invalid \(type.rawValue) value for ‘\(name)’. Edit or clear that field before filtering it."
        case .invalidRegex(let pattern, let message): "Invalid ECMAScript pattern ‘\(pattern)’: \(message)"
        }
    }
}

public enum TaskFilterAttributeType: String, CaseIterable, Codable, Sendable {
    case string, date, numeric, duration, uuid
}

public struct TaskFilterSchema: Sendable {
    var attributes: [UTF8String: TaskFilterAttributeType]
    private var valueOrders: [UTF8String: [String]]
    private static let builtinNames = Set(["description", "project", "status", "uuid", "rtype", "depends", "tags", "mask", "imask", "parent", "recur", "entry", "modified", "start", "end", "due", "scheduled", "wait", "until", "id", "urgency", "last", "template"].map { UTF8String($0) })

    public init(attributes: [(String, TaskFilterAttributeType)] = [], orderedValues: [(String, [String])] = []) {
        valueOrders = Dictionary(orderedValues.map { (UTF8String($0.0), $0.1) }, uniquingKeysWith: { _, new in new })
        self.attributes = Dictionary(attributes.map { (UTF8String($0.0), $0.1) }, uniquingKeysWith: { _, new in new })
    }

    public func orderedValues(for name: String) -> [String]? { valueOrders[UTF8String(name)] }

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
            if let values = definition.values { result.valueOrders[definition.name] = values }
        }
        return result
    }

    public static let standard = TaskFilterSchema(attributes:
        ["description", "project", "priority", "status", "uuid", "rtype", "depends", "tags", "mask", "imask", "parent", "template"].map { ($0, .string) }
        + [("recur", .duration), ("id", .numeric), ("urgency", .numeric)]
        + ["entry", "modified", "start", "end", "due", "scheduled", "wait", "until", "last"].map { ($0, .date) }, orderedValues: [("priority", ["H", "M", "L", ""])])
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
        var values = try TaskExpressionParser(expression, schema: schema)
        if values.hasValueOperators {
            let expression = try values.parse()
            try expression.validate(schema: schema)
            root = .value(expression)
        }
        else {
            var parser = try FilterParser(expression, schema: schema)
            root = try parser.parse()
        }
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
    case value(TaskValueExpression)
    case predicate(FilterPredicate)
    case not(FilterExpression)
    case and(FilterExpression, FilterExpression)
    case or(FilterExpression, FilterExpression)
    case xor(FilterExpression, FilterExpression)

    var requiresWorkingSet: Bool {
        guard !disablesWorkingSet else { return false }
        return hasActiveTag
    }

    private var disablesWorkingSet: Bool {
        switch self {
        case .value(let expression): expression.disablesWorkingSet
        case .or, .xor: true
        case .not(let child): child.disablesWorkingSet
        case .and(let left, let right): left.disablesWorkingSet || right.disablesWorkingSet
        default: false
        }
    }

    private var hasActiveTag: Bool {
        switch self {
        case .value(let expression): expression.hasActiveTag
        case .predicate(.virtualTag(.active, let required)): required
        case .and(let left, let right): left.hasActiveTag || right.hasActiveTag
        case .not(let child): child.hasActiveTag
        default: false
        }
    }

    func includes(_ task: TaskRecord, context: TaskFilterContext) throws -> Bool {
        switch self {
        case .value(let expression): return try expression.evaluation(task, context).selected
        case .all: return true
        case .predicate(let predicate): return try predicate.includes(task, context: context)
        case .not(let expression): return try !expression.includes(task, context: context)
        case .and(let left, let right):
            let lhs = try left.includes(task, context: context), rhs = try right.includes(task, context: context)
            return lhs && rhs
        case .or(let left, let right):
            let lhs = try left.includes(task, context: context), rhs = try right.includes(task, context: context)
            return lhs || rhs
        case .xor(let left, let right): return try left.includes(task, context: context) != right.includes(task, context: context)
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
