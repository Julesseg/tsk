import Foundation

public typealias TaskAttributeType = TaskFilterAttributeType

public struct TaskAttributeDefinition: Identifiable, Codable, Equatable, Sendable {
    public let name: UTF8String
    public let label: String
    public let type: TaskAttributeType
    public var id: UTF8String { name }

    public init(name: String, label: String = "", type: TaskAttributeType) {
        self.name = UTF8String(name)
        self.label = label
        self.type = type
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name && lhs.label.matchesBytes(rhs.label) && lhs.type == rhs.type
    }
}

public protocol TaskAttributeDefinitionsStore: Sendable {
    func load() async throws -> [TaskAttributeDefinition]
    func save(_ definitions: [TaskAttributeDefinition]) async throws
}

public enum TaskAttributeError: Error, Equatable, LocalizedError, Sendable {
    case storageNotConfigured
    case invalidName(String)
    case reservedName(String)
    case missingDefinition(String)
    case invalidValue(String, TaskAttributeType, String)

    public var errorDescription: String? {
        switch self {
        case .storageNotConfigured: "Local attribute-definition storage is unavailable."
        case .invalidName(let name): "Attribute ‘\(name)’ needs a name beginning with a letter or underscore, followed by letters, numbers, underscores, or hyphens."
        case .reservedName(let name): "‘\(name)’ is a Taskwarrior field with its own task editor. Choose a different attribute name."
        case .missingDefinition(let name): "The local definition for ‘\(name)’ no longer exists. Reopen the advanced editor."
        case .invalidValue(let name, let type, let guidance): "‘\(name)’ requires a \(type.rawValue) value. \(guidance)"
        }
    }
}

public extension TaskManager {
    func attributeDefinitions() async throws -> [TaskAttributeDefinition] {
        guard let userAttributeDefinitions else { throw TaskAttributeError.storageNotConfigured }
        return try await userAttributeDefinitions.load().sorted { $0.name < $1.name }
    }

    func saveAttributeDefinition(name: String, label: String = "", type: TaskAttributeType) async throws -> TaskAttributeDefinition {
        let letters = CharacterSet.letters.union(.nonBaseCharacters)
        let first = name.unicodeScalars.first
        guard let first, first == "_" || CharacterSet.letters.contains(first),
              name.unicodeScalars.allSatisfy({ letters.contains($0) || CharacterSet.decimalDigits.contains($0) || $0 == "_" || $0 == "-" }) else { throw TaskAttributeError.invalidName(name) }
        guard !TaskFilterSchema.standard.contains(name) else { throw TaskAttributeError.reservedName(name) }
        guard let userAttributeDefinitions else { throw TaskAttributeError.storageNotConfigured }
        let lease = try await beginMutation()
        defer { endMutation(lease) }
        var definitions = try await userAttributeDefinitions.load()
        let definition = TaskAttributeDefinition(name: name, label: label, type: type)
        definitions.removeAll { $0.name == definition.name }
        definitions.append(definition)
        try await userAttributeDefinitions.save(definitions)
        return definition
    }

    func deleteAttributeDefinition(name: String) async throws {
        guard let userAttributeDefinitions else { throw TaskAttributeError.storageNotConfigured }
        let lease = try await beginMutation()
        defer { endMutation(lease) }
        var definitions = try await userAttributeDefinitions.load()
        guard definitions.contains(where: { $0.name == UTF8String(name) }) else { throw TaskAttributeError.missingDefinition(name) }
        definitions.removeAll { $0.name == UTF8String(name) }
        try await userAttributeDefinitions.save(definitions)
    }

    func effectiveFilterSchema(base: TaskFilterSchema = .standard) async throws -> TaskFilterSchema {
        let definitions = try await userAttributeDefinitions?.load() ?? []
        return base.adding(definitions)
    }
}
