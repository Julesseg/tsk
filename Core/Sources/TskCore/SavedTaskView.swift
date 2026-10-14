import Foundation

public struct SavedTaskView: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let expression: String

    public init(id: UUID = UUID(), name: String, expression: String) {
        self.id = id
        self.name = name
        self.expression = expression
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.name.matchesBytes(rhs.name) && lhs.expression.matchesBytes(rhs.expression)
    }
}

public protocol TaskViewDefinitionsStore: Sendable {
    func load() async throws -> [SavedTaskView]
    func save(_ definitions: [SavedTaskView]) async throws
}

public enum TaskViewError: Error, Equatable, LocalizedError, Sendable {
    case emptyName, storageNotConfigured, missingView(UUID)

    public var errorDescription: String? {
        switch self {
        case .emptyName: "Enter a name for this view."
        case .storageNotConfigured: "Local saved-view storage is unavailable."
        case .missingView: "This saved view no longer exists. Reopen the view list."
        }
    }
}

extension TaskManager {
    public func savedViews() async throws -> [SavedTaskView] {
        guard let viewDefinitions else { throw TaskViewError.storageNotConfigured }
        return try await viewDefinitions.load()
    }

    public func saveView(id: UUID? = nil, name: String, expression: String, schema: TaskFilterSchema = .standard) async throws -> SavedTaskView {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw TaskViewError.emptyName }
        try validateFilter(expression, schema: schema)
        guard let viewDefinitions else { throw TaskViewError.storageNotConfigured }
        let lease = try await beginMutation()
        defer { endMutation(lease) }
        var definitions = try await viewDefinitions.load()
        let view = SavedTaskView(id: id ?? UUID(), name: name, expression: expression)
        if let id {
            guard let index = definitions.firstIndex(where: { $0.id == id }) else { throw TaskViewError.missingView(id) }
            definitions[index] = view
        } else { definitions.append(view) }
        try await viewDefinitions.save(definitions)
        return view
    }

    public func deleteView(id: UUID) async throws {
        guard let viewDefinitions else { throw TaskViewError.storageNotConfigured }
        let lease = try await beginMutation()
        defer { endMutation(lease) }
        var definitions = try await viewDefinitions.load()
        guard definitions.contains(where: { $0.id == id }) else { throw TaskViewError.missingView(id) }
        definitions.removeAll { $0.id == id }
        try await viewDefinitions.save(definitions)
    }
}
