import Foundation

public enum TaskProjectSelection: Hashable, Sendable {
    case all
    case unassigned
    case project(String)

    public func includes(_ task: TaskRecord) -> Bool {
        switch self {
        case .all: true
        case .unassigned: task.project.isEmpty
        case .project(let name): task.project == name
        }
    }

    public var projectName: String? {
        if case .project(let name) = self { return name }
        return nil
    }
}

extension TaskRecord {
    public var project: String { attributes["project"] ?? "" }
    public var priority: String { attributes["priority"] ?? "" }
    public var tags: [String] { TaskOrganization.tags(in: attributes) }
}

extension TaskDraft {
    public var project: String {
        get { attributes["project"] ?? "" }
        set { attributes["project"] = newValue.isEmpty ? nil : newValue }
    }

    public var priority: String {
        get { attributes["priority"] ?? "" }
        set { attributes["priority"] = newValue.isEmpty ? nil : newValue }
    }

    public var tags: [String] { TaskOrganization.tags(in: attributes) }

    public mutating func addTag(_ tag: String) throws {
        try TaskOrganization.validateTag(tag)
        let key = "tag_\(tag)"
        if attributes[key] == nil { attributes[key] = "" }
    }

    public mutating func removeTag(_ tag: String) {
        attributes.removeValue(forKey: "tag_\(tag)")
    }
}

extension TaskManager {
    public func projects(query: TaskQuery = .all) async throws -> [String] {
        let records = try await tasks(query: query)
        return Array(Set(records.map(\.project).filter { !$0.isEmpty })).sorted()
    }
}

enum TaskOrganization {
    static func tags(in attributes: [String: String]) -> [String] {
        attributes.keys.compactMap { key in
            guard key.hasPrefix("tag_"), key.count > 4 else { return nil }
            return String(key.dropFirst(4))
        }.sorted()
    }

    static func validateTag(_ tag: String) throws {
        let scalars = tag.unicodeScalars
        guard let first = scalars.first,
              !(48...57).contains(first.value),
              !"+-*/()<>^!%=~".unicodeScalars.contains(first),
              !scalars.contains(where: { $0.properties.isWhitespace }),
              !scalars.dropFirst().contains(":"),
              !scalars.allSatisfy({ (65...90).contains($0.value) }) else {
            throw TaskManagementError.invalidTag(tag)
        }
    }

    static func normalizedAttributes(_ attributes: [String: String]) throws -> [String: String] {
        let patch = try normalizedChanges(attributes.mapValues(Optional.some), original: [:])
        return patch.reduce(into: [:]) { result, change in result[change.key] = change.value }
    }

    static func normalizedChanges(_ changes: [String: String?], original: [String: String]) throws -> [String: String?] {
        var patch = changes
        if changes.keys.contains("project") {
            let project = changes["project"] ?? nil
            patch.updateValue(project?.isEmpty == false ? project : nil, forKey: "project")
        }
        if changes.keys.contains("priority") {
            let priority = changes["priority"] ?? nil
            guard priority == nil || priority == "" || ["H", "M", "L"].contains(priority ?? "") else {
                throw TaskManagementError.invalidPriority(priority ?? "")
            }
            patch.updateValue(priority?.isEmpty == false ? priority : nil, forKey: "priority")
        }
        let tagKeys = changes.keys.filter { $0.hasPrefix("tag_") }
        for key in tagKeys where changes[key] != .some(nil) {
            try validateTag(String(key.dropFirst(4)))
        }
        if !tagKeys.isEmpty {
            var attributes = original
            for (key, value) in patch { attributes[key] = value }
            let tags = tags(in: attributes)
            patch.updateValue(tags.isEmpty ? nil : tags.joined(separator: ","), forKey: "tags")
        }
        return patch
    }
}
