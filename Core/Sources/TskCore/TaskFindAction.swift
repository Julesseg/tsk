import Foundation

public enum FindTaskStatus: String, CaseIterable, Sendable {
    case unfinished, completed, all

    func includes(_ task: TaskRecord) -> Bool {
        switch self {
        case .unfinished: task.status == "pending"
        case .completed: task.status == "completed"
        case .all: task.status == "pending" || task.status == "completed"
        }
    }
}

public enum FindTaskSort: String, CaseIterable, Sendable {
    case newest = "created-desc"
    case oldest = "created-asc"
    case description = "description-asc"
    case scheduled = "scheduled-asc"
    case deadline = "deadline-asc"
    case waitingUntil = "waiting-until-asc"
    case priority = "priority-desc"

    func precedes(_ lhs: TaskRecord, _ rhs: TaskRecord) -> Bool {
        switch self {
        case .newest, .oldest:
            let left = Self.created(lhs), right = Self.created(rhs)
            if left != right { return Self.datePrecedes(left, right, descending: self == .newest) }
        case .description:
            let left = UTF8String(lhs.description), right = UTF8String(rhs.description)
            if left != right { return left < right }
        case .scheduled, .deadline, .waitingUntil:
            let key = self == .scheduled ? "scheduled" : self == .deadline ? "due" : "wait"
            let left = Self.date(lhs, key: key), right = Self.date(rhs, key: key)
            if left != right { return Self.datePrecedes(left, right) }
        case .priority:
            let ranks = ["H": 0, "M": 1, "L": 2]
            let left = ranks[lhs.priority] ?? 3, right = ranks[rhs.priority] ?? 3
            if left != right { return left < right }
        }
        let left = Self.created(lhs), right = Self.created(rhs)
        if left != right { return Self.datePrecedes(left, right, descending: true) }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func created(_ task: TaskRecord) -> Date? { date(task, key: "entry") }

    private static func date(_ task: TaskRecord, key: String) -> Date? {
        guard let raw = task.attributes[key], let seconds = Double(raw), seconds.isFinite,
              abs(seconds) <= 253402300799 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private static func datePrecedes(_ lhs: Date?, _ rhs: Date?, descending: Bool = false) -> Bool {
        switch (lhs, rhs) {
        case (.some(let left), .some(let right)): descending ? left > right : left < right
        case (.some, .none): true
        default: false
        }
    }
}

public struct TaskDateRange: Equatable, Sendable {
    public var from: Date?
    public var through: Date?

    public init(from: Date? = nil, through: Date? = nil) {
        self.from = from
        self.through = through
    }

    func validate() throws {
        for date in [from, through].compactMap({ $0 }) {
            let seconds = date.timeIntervalSince1970
            guard seconds.isFinite, abs(seconds) <= 253402300799 else { throw TaskActionError.invalidInput("Invalid date bound.") }
        }
        if let from, let through, from > through { throw TaskActionError.invalidInput("A date range must start at or before its end.") }
    }

    func includes(_ date: Date?) -> Bool {
        guard from != nil || through != nil else { return true }
        guard let date else { return false }
        return from.map { date >= $0 } != false && through.map { date <= $0 } != false
    }
}

public struct FindTasksInput: Equatable, Sendable {
    public var description: String
    public var project: String?
    public var tags: [String]
    public var status: FindTaskStatus
    public var priority: String?
    public var scheduled: TaskDateRange
    public var deadline: TaskDateRange
    public var waitingUntil: TaskDateRange
    public var sort: FindTaskSort
    public var limit: Int?
    public var offset: Int

    public init(description: String = "", project: String? = nil, tags: [String] = [], status: FindTaskStatus = .unfinished, priority: String? = nil, scheduled: TaskDateRange = TaskDateRange(), deadline: TaskDateRange = TaskDateRange(), waitingUntil: TaskDateRange = TaskDateRange(), sort: FindTaskSort = .newest, limit: Int? = nil, offset: Int = 0) {
        self.description = description
        self.project = project
        self.tags = tags
        self.status = status
        self.priority = priority
        self.scheduled = scheduled
        self.deadline = deadline
        self.waitingUntil = waitingUntil
        self.sort = sort
        self.limit = limit
        self.offset = offset
    }

    public func validate() throws {
        if let priority, !["", "H", "M", "L"].contains(priority) { throw TaskManagementError.invalidPriority(priority) }
        try scheduled.validate()
        try deadline.validate()
        try waitingUntil.validate()
        guard offset >= 0, limit.map({ $0 > 0 }) != false else { throw TaskActionError.invalidInput("Offset must be nonnegative and limit must be positive.") }
    }

    func includes(_ task: TaskRecord) -> Bool {
        status.includes(task)
            && (description.isEmpty || task.description.range(of: description, options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX")) != nil)
            && (project.map { task.project.matchesBytes($0) } ?? true)
            && tags.allSatisfy { tag in task.tags.contains { $0.matchesBytes(tag) } }
            && (priority.map { task.priority == $0 } ?? true)
            && scheduled.includes(task.plannedDate)
            && deadline.includes(task.deadline)
            && waitingUntil.includes(task.waitUntil)
    }
}

public extension TaskManager {
    func findTasks(_ input: FindTasksInput = FindTasksInput()) async throws -> [TaskRecord] {
        try input.validate()
        let matches = try await replica.tasks().filter(input.includes).sorted(by: input.sort.precedes).dropFirst(input.offset)
        return Array(matches.prefix(input.limit ?? matches.count))
    }
}
