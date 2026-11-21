import Foundation

public enum TaskActionURL: Equatable, Sendable {
    case add(AddTaskInput)
    case find(FindTasksInput)
    case modify(UUID, ModifyTaskInput)
    case openTask(UUID)
    case complete(UUID)
    case delete(UUID)
    case openView(TaskNavigationView)

    public init(url: URL) throws {
        let components = try Self.components(url)
        let items = components.queryItems ?? []
        let allowed: Set<String>
        switch components.host {
        case "add": allowed = ["description", "project", "tags", "priority", "scheduled", "deadline", "x-success", "x-error"]
        case "find": allowed = ["description", "project", "tags", "status", "priority", "scheduled-from", "scheduled-through", "deadline-from", "deadline-through", "sort", "limit", "offset", "x-success", "x-error"]
        case "modify": allowed = ["id", "description", "project", "tags", "tag-operation", "priority", "scheduled", "deadline", "clear-project", "clear-priority", "clear-scheduled", "clear-deadline", "x-success", "x-error"]
        case "delete": allowed = ["id", "x-success", "x-error"]
        case "complete": allowed = ["id", "x-success", "x-error"]
        case "open-task": allowed = ["id", "x-success", "x-error"]
        case "open-view": allowed = ["view", "project", "id", "x-success", "x-error"]
        default: throw TaskActionError.invalidInput("Unsupported tsk action.")
        }
        var values: [String: [String]] = [:]
        for item in items {
            guard allowed.contains(item.name), let value = item.value,
                  item.name == "tags" || values[item.name] == nil else {
                throw TaskActionError.invalidInput("Unknown, duplicate, or missing value for ‘\(item.name)’.")
            }
            values[item.name, default: []].append(value)
        }
        _ = try TaskActionCallbacks(url: url)
        if components.host == "open-view" {
            let view: TaskNavigationView
            switch values["view"]?.first {
            case "today": view = .today
            case "inbox": view = .inbox
            case "unfinished": view = .unfinished
            case "done": view = .done
            case "projects": view = .projects
            case "project":
                guard let name = values["project"]?.first, !name.isEmpty else { throw TaskActionError.invalidInput("Open View requires an exact project name.") }
                view = .project(name)
            default: throw TaskActionError.invalidInput("Choose today, inbox, projects, or an exact project.")
            }
            guard (values["project"] == nil || { if case .project = view { return true }; return false }()), values["id"] == nil else { throw TaskActionError.invalidInput("Arguments do not belong to this view.") }
            self = .openView(view)
        } else if components.host == "open-task" || components.host == "complete" || components.host == "delete" {
            let id = try Self.taskID(values["id"]?.first)
            if components.host == "complete" { self = .complete(id) }
            else if components.host == "delete" { self = .delete(id) }
            else { self = .openTask(id) }
        } else if components.host == "find" {
            guard let status = FindTaskStatus(rawValue: values["status"]?.first ?? "unfinished"),
                  let sort = FindTaskSort(rawValue: values["sort"]?.first ?? "created-desc") else {
                throw TaskActionError.invalidInput("Unsupported Find status or sort choice.")
            }
            func integer(_ key: String) throws -> Int? {
                guard let raw = values[key]?.first else { return nil }
                guard !raw.isEmpty, raw.utf8.allSatisfy({ (48...57).contains($0) }), let value = Int(raw) else {
                    throw TaskActionError.invalidInput("\(key) requires a nonnegative integer.")
                }
                return value
            }
            func range(_ key: String) throws -> TaskDateRange {
                try TaskDateRange(from: Self.date(values[key + "-from"]?.first), through: Self.date(values[key + "-through"]?.first))
            }
            let input = try FindTasksInput(description: values["description"]?.first ?? "", project: values["project"]?.first,
                                           tags: values["tags"] ?? [], status: status, priority: values["priority"]?.first,
                                           scheduled: range("scheduled"), deadline: range("deadline"),
                                           sort: sort, limit: integer("limit"), offset: integer("offset") ?? 0)
            try input.validate()
            self = .find(input)
        } else if components.host == "modify" {
            let id = try Self.taskID(values["id"]?.first)
            guard let operation = TaskTagOperation(rawValue: values["tag-operation"]?.first ?? "add") else { throw TaskActionError.invalidInput("Tag operation must be add, remove, replace, or clear.") }
            let input = ModifyTaskInput(description: values["description"]?.first, project: values["project"]?.first, tags: values["tags"], tagOperation: operation, priority: values["priority"]?.first,
                                        scheduled: try Self.date(values["scheduled"]?.first), deadline: try Self.date(values["deadline"]?.first),
                                        clearProject: try Self.clear(values["clear-project"]?.first), clearPriority: try Self.clear(values["clear-priority"]?.first), clearScheduled: try Self.clear(values["clear-scheduled"]?.first), clearDeadline: try Self.clear(values["clear-deadline"]?.first))
            _ = try input.validatedChanges(for: TaskRecord(id: id, attributes: [:]))
            self = .modify(id, input)
        } else {
            let input = AddTaskInput(description: values["description"]?.first ?? "", project: values["project"]?.first, tags: values["tags"] ?? [], priority: values["priority"]?.first,
                                     scheduled: try Self.date(values["scheduled"]?.first), deadline: try Self.date(values["deadline"]?.first))
            _ = try input.validatedDraft()
            self = .add(input)
        }
    }

    private static func taskID(_ raw: String?) throws -> UUID {
        guard let raw, raw.count == 36, let id = UUID(uuidString: raw) else { throw TaskActionError.invalidInput("This action requires one full task UUID.") }
        return id
    }

    private static func clear(_ raw: String?) throws -> Bool {
        guard let raw else { return false }
        guard ["true", "false"].contains(raw) else { throw TaskActionError.invalidInput("Clear controls must be true or false.") }
        return raw == "true"
    }

    static func components(_ url: URL) throws -> URLComponents {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "tsk", components.user == nil, components.password == nil,
              components.port == nil, components.path.isEmpty, components.fragment == nil else {
            throw TaskActionError.invalidInput("Use a simple tsk:// action URL without a path, credentials, port, or fragment.")
        }
        for part in (components.percentEncodedQuery ?? "").split(separator: "%").dropFirst() {
            guard part.count >= 2, part.prefix(2).allSatisfy({ $0.isHexDigit }) else { throw TaskActionError.invalidInput("Malformed URL encoding.") }
        }
        return components
    }

    private static func date(_ raw: String?) throws -> Date? {
        guard let raw else { return nil }
        let pattern = #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$"#
        guard raw.range(of: pattern, options: .regularExpression) != nil else { throw TaskActionError.invalidInput("Dates require an ISO 8601 timestamp with an explicit timezone.") }
        let wallTime = DateFormatter()
        wallTime.locale = Locale(identifier: "en_US_POSIX")
        wallTime.calendar = Calendar(identifier: .gregorian)
        wallTime.timeZone = TimeZone(secondsFromGMT: 0)
        wallTime.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        wallTime.isLenient = false
        let clock = String(raw.prefix(19))
        guard let local = wallTime.date(from: clock), wallTime.string(from: local) == clock else { throw TaskActionError.invalidInput("Invalid calendar date or time.") }
        if !raw.hasSuffix("Z") {
            let offset = raw.suffix(6)
            guard let hours = Int(offset.dropFirst().prefix(2)), let minutes = Int(offset.suffix(2)), hours <= 23, minutes <= 59 else { throw TaskActionError.invalidInput("Invalid timezone offset.") }
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = raw.contains(".") ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        guard let date = formatter.date(from: raw) else { throw TaskActionError.invalidInput("Invalid date timestamp.") }
        return date
    }
}
