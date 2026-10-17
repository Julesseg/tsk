import Foundation

public enum TaskViewReference: Hashable, Sendable {
    case query(TaskQuery), project(UTF8String), unassigned, custom(UUID)

    public var id: String {
        switch self {
        case .query(let query): "query:" + query.rawValue
        case .project(let name): "project:" + Data(name.rawValue.utf8).base64EncodedString()
        case .unassigned: "unassigned"
        case .custom(let id): "custom:" + id.uuidString.lowercased()
        }
    }

    public init(id: String) throws {
        if id == "unassigned" { self = .unassigned; return }
        if id.hasPrefix("query:"), let query = TaskQuery(rawValue: String(id.dropFirst(6))) { self = .query(query); return }
        if id.hasPrefix("custom:"), let uuid = UUID(uuidString: String(id.dropFirst(7))) { self = .custom(uuid); return }
        if id.hasPrefix("project:"), let data = Data(base64Encoded: String(id.dropFirst(8))), let name = String(data: data, encoding: .utf8) { self = .project(UTF8String(name)); return }
        throw TaskManagementError.storage("This task view is no longer registered. Edit the widget and choose an available view.")
    }
}

public struct RegisteredTaskView: Identifiable, Equatable, Sendable {
    public let reference: TaskViewReference
    public let name: String
    public var id: String { reference.id }
    public init(reference: TaskViewReference, name: String) { self.reference = reference; self.name = name }
    public static func == (left: Self, right: Self) -> Bool { left.reference == right.reference && left.name.matchesBytes(right.name) }
}

extension TaskManager {
    public func registeredViews() async throws -> [RegisteredTaskView] {
        var views: [RegisteredTaskView] = [
            .init(reference: .query(.today), name: "Today"), .init(reference: .query(.upcoming), name: "Upcoming"),
            .init(reference: .query(.unfinished), name: "Unfinished"), .init(reference: .query(.completed), name: "Completed"),
            .init(reference: .query(.all), name: "All tasks"), .init(reference: .unassigned, name: "No project · Unfinished")
        ]
        views += try await projects().map { .init(reference: .project(UTF8String($0)), name: $0 + " · Unfinished") }
        views += try await savedViews().map { .init(reference: .custom($0.id), name: $0.name) }
        return views
    }

    public func viewSnapshot(reference: TaskViewReference) async throws -> TaskViewSnapshot {
        switch reference {
        case .query(let query): return try await viewSnapshot(query: query)
        case .project(let name): return try await viewSnapshot(query: .unfinished, project: .project(name.rawValue))
        case .unassigned: return try await viewSnapshot(query: .unfinished, project: .unassigned)
        case .custom(let id):
            guard let definition = try await savedViews().first(where: { $0.id == id }) else { throw TaskViewError.missingView(id) }
            return try await viewSnapshot(filter: definition.expression)
        }
    }
}
