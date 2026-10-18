import Foundation

public struct TaskSpotlightItem: Equatable, Sendable {
    public let taskID: UUID
    public let identifier: String
    public let title: String
    public let summary: String

    public static func projected(from tasks: [TaskRecord], namespace: String) -> [Self] {
        tasks.filter { $0.status == "pending" && !$0.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map { task in
            Self(taskID: task.id, identifier: identifier(for: task.id, namespace: namespace), title: task.description, summary: ([task.project] + task.tags.sorted { UTF8String($0) < UTF8String($1) }).filter { !$0.isEmpty }.joined(separator: " · "))
        }.sorted { $0.identifier < $1.identifier }
    }

    public static func identifier(for id: UUID, namespace: String) -> String { namespace + "/task/" + id.uuidString.lowercased() }

    public static func taskID(from identifier: String, namespace: String) throws -> UUID {
        let prefix = namespace + "/task/"
        guard identifier.utf8.starts(with: prefix.utf8) else { throw TaskSpotlightError.invalidIdentifier }
        let raw = String(decoding: identifier.utf8.dropFirst(prefix.utf8.count), as: UTF8.self)
        guard let id = UUID(uuidString: raw), raw.matchesBytes(id.uuidString.lowercased()) else { throw TaskSpotlightError.invalidIdentifier }
        return id
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.taskID == rhs.taskID && lhs.identifier.matchesBytes(rhs.identifier) && lhs.title.matchesBytes(rhs.title) && lhs.summary.matchesBytes(rhs.summary)
    }
}

public protocol TaskSpotlightIndex: Sendable {
    var namespace: String { get }
    func replace(_ items: [TaskSpotlightItem]) async throws
}

public enum TaskSpotlightError: Error, Equatable, LocalizedError, Sendable {
    case invalidIdentifier, unavailable(UUID)
    public var errorDescription: String? {
        switch self {
        case .invalidIdentifier: "This Spotlight result does not identify a task in this task library."
        case .unavailable: "This task is no longer available. The Spotlight result may be out of date."
        }
    }
}

public extension TaskManager {
    func reconcileSpotlight(using index: any TaskSpotlightIndex) async throws -> Int {
        let items = TaskSpotlightItem.projected(from: try await tasks(), namespace: index.namespace)
        try await index.replace(items)
        return items.count
    }

    func resolveSpotlight(identifier: String, namespace: String) async throws -> TaskRecord {
        let id = try TaskSpotlightItem.taskID(from: identifier, namespace: namespace)
        let records = try await tasks()
        guard let task = records.first(where: { $0.id == id }), task.status != "deleted" else { throw TaskSpotlightError.unavailable(id) }
        return task
    }
}
