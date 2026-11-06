import Foundation

public enum TaskActionURL: Equatable, Sendable {
    case add(AddTaskInput)
    case openTask(UUID)

    public init(url: URL) throws {
        let components = try Self.components(url)
        let items = components.queryItems ?? []
        let allowed: Set<String>
        switch components.host {
        case "add": allowed = ["description", "project", "tags", "priority", "scheduled", "deadline", "waiting-until", "x-success", "x-error"]
        case "open-task": allowed = ["id"]
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
        if components.host == "open-task" {
            guard let raw = values["id"]?.first, raw.count == 36, let id = UUID(uuidString: raw) else { throw TaskActionError.invalidInput("Open Task requires a full UUID.") }
            self = .openTask(id)
        } else {
            _ = try TaskActionCallbacks(url: url)
            let input = AddTaskInput(description: values["description"]?.first ?? "", project: values["project"]?.first, tags: values["tags"] ?? [], priority: values["priority"]?.first,
                                     scheduled: try Self.date(values["scheduled"]?.first), deadline: try Self.date(values["deadline"]?.first), waitingUntil: try Self.date(values["waiting-until"]?.first))
            _ = try input.validatedDraft()
            self = .add(input)
        }
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
