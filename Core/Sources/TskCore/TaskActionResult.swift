import Foundation

public struct TaskActionResult: Encodable, Sendable {
    public let uuid: String
    public let description: String
    public let project: String?
    public let tags: [String]
    public let priority: String?
    public let scheduled: String?
    public let deadline: String?
    public let waitingUntil: String?
    public let status: String
    public let openTaskURL: URL

    public init(_ task: TaskRecord) {
        uuid = task.id.uuidString
        description = task.description
        project = task.project.isEmpty ? nil : task.project
        tags = task.tags
        priority = task.priority.isEmpty ? nil : task.priority
        let formatter = ISO8601DateFormatter()
        scheduled = task.plannedDate.map(formatter.string)
        deadline = task.deadline.map(formatter.string)
        waitingUntil = task.waitUntil.map(formatter.string)
        status = task.status
        openTaskURL = URL(string: "tsk://open-task?id=" + task.id.uuidString)!
    }

    private enum CodingKeys: String, CodingKey {
        case uuid, description, project, tags, priority, scheduled, deadline, waitingUntil, status, openTaskURL
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(uuid, forKey: .uuid)
        try values.encode(description, forKey: .description)
        try values.encode(project, forKey: .project)
        try values.encode(tags, forKey: .tags)
        try values.encode(priority, forKey: .priority)
        try values.encode(scheduled, forKey: .scheduled)
        try values.encode(deadline, forKey: .deadline)
        try values.encode(waitingUntil, forKey: .waitingUntil)
        try values.encode(status, forKey: .status)
        try values.encode(openTaskURL, forKey: .openTaskURL)
    }
}

public struct TaskActionCallbacks: Sendable {
    public static let maximumURLBytes = 8192
    private let success: URL?
    private let error: URL?

    public init(url: URL) throws {
        let items = try TaskActionURL.components(url).queryItems ?? []
        success = try Self.callback(items, name: "x-success")
        error = try Self.callback(items, name: "x-error")
    }

    public func successURL(for task: TaskRecord) throws -> URL? {
        try (success ?? error).map { try Self.url($0, payload: Success(task: TaskActionResult(task))) }
    }

    public func errorURL(code: String, message: String, savedTaskID: UUID? = nil) throws -> URL? {
        guard let base = error ?? success else { return nil }
        let failure = Failure(savedLocally: savedTaskID != nil, uuid: savedTaskID?.uuidString, error: FailureDetail(code: code, message: message))
        do { return try Self.url(base, payload: failure) }
        catch TaskActionError.resultTooLarge {
            return try Self.url(base, payload: Failure(savedLocally: savedTaskID != nil, uuid: savedTaskID?.uuidString, error: FailureDetail(code: "result_too_large", message: "The error details exceed the callback URL limit. They were not truncated.")))
        }
    }

    private static func callback(_ items: [URLQueryItem], name: String) throws -> URL? {
        let matches = items.filter { $0.name == name }
        guard !matches.isEmpty else { return nil }
        guard matches.count == 1, let raw = matches[0].value, raw.removingPercentEncoding != nil,
              raw.utf8.count <= 4096, let components = URLComponents(string: raw),
              let scheme = components.scheme?.lowercased(),
              !["tsk", "file", "javascript", "data", "about"].contains(scheme),
              components.user == nil, components.password == nil, components.fragment == nil,
              !["http", "https"].contains(scheme) || !(components.host ?? "").isEmpty,
              !(components.host ?? "").isEmpty || !components.path.isEmpty,
              !(components.queryItems ?? []).contains(where: { $0.name == "result" }), let url = components.url else {
            throw TaskActionError.invalidInput("Invalid \(name) callback URL. Use an absolute caller URL without a fragment, credentials, or a result argument (maximum 4096 bytes).")
        }
        return url
    }

    private static func url<T: Encodable>(_ base: URL, payload: T) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(payload)
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        let result = URLQueryItem(name: "result", value: String(decoding: data, as: UTF8.self))
        var encodedResult = URLComponents()
        encodedResult.queryItems = [result]
        let query = encodedResult.percentEncodedQuery!.replacingOccurrences(of: "+", with: "%2B")
        components.percentEncodedQuery = [components.percentEncodedQuery, query].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "&")
        guard let url = components.url, url.absoluteString.utf8.count <= maximumURLBytes else { throw TaskActionError.resultTooLarge }
        return url
    }

    private struct Success: Encodable {
        let success = true
        let savedLocally = true
        let task: TaskActionResult
    }

    private struct Failure: Encodable {
        let success = false
        let savedLocally: Bool
        let uuid: String?
        let error: FailureDetail
    }

    private struct FailureDetail: Encodable {
        let code: String
        let message: String
    }
}

public enum TaskActionFailureCode: String, Sendable {
    case invalidInput = "invalid_input"
    case storageError = "storage_error"
    case navigationError = "navigation_error"
    case taskNotFound = "task_not_found"
    case taskDeleted = "task_deleted"
    case resultTooLarge = "result_too_large"
    case resultError = "result_error"

    public init(error: any Error, savedLocally: Bool) {
        if error as? TaskActionError == .resultTooLarge { self = .resultTooLarge }
        else if savedLocally { self = .resultError }
        else if case .navigationFailed = error as? TaskActionError { self = .navigationError }
        else if let taskError = error as? TaskManagementError {
            switch taskError {
            case .storage: self = .storageError
            case .taskNotFound: self = .taskNotFound
            case .taskDeleted: self = .taskDeleted
            default: self = .invalidInput
            }
        } else { self = error is TaskActionError ? .invalidInput : .storageError }
    }
}
