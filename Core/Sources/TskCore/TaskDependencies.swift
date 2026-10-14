import Foundation

public enum TaskDependencyIssue: Equatable, Sendable {
    case invalidReference
    case missingReference
    case selfReference
    case cycle
}

public struct TaskDependencyLink: Identifiable, Equatable, Sendable {
    public let reference: String
    public let task: TaskRecord?
    public let issue: TaskDependencyIssue?
    public var id: Data { Data(reference.utf8) }
}

public extension TaskRecord {
    var dependencyReferences: [String] {
        attributes.keys.compactMap { key in
            guard key.utf8.starts(with: "dep_".utf8) else { return nil }
            return String(decoding: key.utf8.dropFirst(4), as: UTF8.self)
        }.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
    }

    func dependencyLinks(in tasks: [TaskRecord]) -> [TaskDependencyLink] {
        let byReference = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id.uuidString.lowercased(), $0) })
        return dependencyReferences.map { reference in
            guard reference.utf8.count == 36, UUID(uuidString: reference) != nil else {
                return TaskDependencyLink(reference: reference, task: nil, issue: .invalidReference)
            }
            let target = byReference[reference]
            let issue: TaskDependencyIssue?
            if target == nil { issue = .missingReference }
            else if target?.id == id { issue = .selfReference }
            else if let target, TaskDependencies.hasPath(from: target.id, to: id, tasks: tasks) { issue = .cycle }
            else { issue = nil }
            return TaskDependencyLink(reference: reference, task: target, issue: issue)
        }
    }
}

public extension TaskManager {
    func dependencyLinks(id: UUID) async throws -> [TaskDependencyLink] {
        let records = try await tasks()
        guard let record = records.first(where: { $0.id == id }) else { throw TaskManagementError.taskNotFound(id) }
        return record.dependencyLinks(in: records)
    }

    func addDependency(id: UUID, prerequisiteID: UUID) async throws -> TaskRecord {
        let lease = try await beginMutation()
        defer { endMutation(lease) }
        try Task.checkCancellation()
        let records = try await tasks()
        guard let source = records.first(where: { $0.id == id }) else { throw TaskManagementError.taskNotFound(id) }
        guard source.canEdit else { throw TaskManagementError.unsupportedTaskKind }
        guard records.contains(where: { $0.id == prerequisiteID }) else { throw TaskManagementError.taskNotFound(prerequisiteID) }
        guard id != prerequisiteID else { throw TaskManagementError.dependencySelfReference }
        let reference = prerequisiteID.uuidString.lowercased()
        let key = "dep_\(reference)"
        if source.attributes[key] != nil { return source }
        guard !TaskDependencies.hasPath(from: prerequisiteID, to: id, tasks: records) else { throw TaskManagementError.dependencyCycle }
        let references = (source.dependencyReferences + [reference]).sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        let saved = try await replica.update(id: id, changes: [key: "x", "depends": references.joined(separator: ","), "modified": String(Int(now().timeIntervalSince1970))])
        localChangeWasCommitted()
        return saved
    }
}

private enum TaskDependencies {
    static func hasPath(from start: UUID, to target: UUID, tasks: [TaskRecord]) -> Bool {
        let byReference = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id.uuidString.lowercased(), $0) })
        var pending = [start.uuidString.lowercased()]
        var visited = Set<String>()
        while let reference = pending.popLast() {
            guard visited.insert(reference).inserted, let record = byReference[reference] else { continue }
            if record.id == target { return true }
            pending.append(contentsOf: record.dependencyReferences)
        }
        return false
    }
}

public extension TaskManager {
    func removeDependency(id: UUID, reference: String) async throws -> TaskRecord {
        let lease = try await beginMutation()
        defer { endMutation(lease) }
        try Task.checkCancellation()
        let source = try await task(id: id)
        guard source.canEdit else { throw TaskManagementError.unsupportedTaskKind }
        let key = "dep_\(reference)"
        guard source.attributes[key] != nil else { throw TaskManagementError.dependencyReferenceNotFound(reference) }
        let remaining = source.dependencyReferences.filter { !($0.utf8.elementsEqual(reference.utf8)) }
        var patch: TaskAttributePatch = ["modified": String(Int(now().timeIntervalSince1970))]
        patch.updateValue(nil, forKey: key)
        patch.updateValue(remaining.isEmpty ? nil : remaining.joined(separator: ","), forKey: "depends")
        let saved = try await replica.update(id: id, changes: patch)
        localChangeWasCommitted()
        return saved
    }
}
