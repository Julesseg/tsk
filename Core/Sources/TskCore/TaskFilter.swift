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

public enum TaskFilterAttributeType: String, Codable, Sendable {
    case string, date, numeric, duration
}

public struct TaskFilterSchema: Sendable {
    var attributes: [UTF8String: TaskFilterAttributeType]

    public init(attributes: [(String, TaskFilterAttributeType)] = []) {
        self.attributes = Dictionary(attributes.map { (UTF8String($0.0), $0.1) }, uniquingKeysWith: { _, new in new })
    }

    public static let standard = TaskFilterSchema(attributes:
        ["description", "project", "priority", "status", "uuid", "rtype", "depends", "tags", "mask", "imask", "parent"].map { ($0, .string) }
        + [("recur", .duration)]
        + ["entry", "modified", "start", "end", "due", "scheduled", "wait", "until"].map { ($0, .date) })
}

struct TaskFilterContext: Sendable {
    let tasks: [TaskRecord]
    let now: Date
    let calendar: Calendar
}

struct CompiledTaskFilter: Sendable {
    let root: FilterExpression

    init(_ expression: String, schema: TaskFilterSchema) throws {
        var parser = try FilterParser(expression, schema: schema)
        root = try parser.parse()
    }

    func includes(_ task: TaskRecord, context: TaskFilterContext) throws -> Bool {
        try root.includes(task, context: context)
    }
}

indirect enum FilterExpression: Sendable {
    case all
    case predicate(FilterPredicate)
    case not(FilterExpression)
    case and(FilterExpression, FilterExpression)
    case or(FilterExpression, FilterExpression)
    case xor(FilterExpression, FilterExpression)

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
        let filter = try CompiledTaskFilter(expression, schema: schema)
        let records = try await tasks()
        let context = TaskFilterContext(tasks: records, now: now(), calendar: calendar)
        let visible = try records.filter { try filter.includes($0, context: context) }
        return TaskViewSnapshot(tasks: visible, allTasks: records, projects: TaskProjectSelection.names(in: records))
    }

    public func validateFilter(_ expression: String, schema: TaskFilterSchema = .standard) throws {
        _ = try CompiledTaskFilter(expression, schema: schema)
    }
}
