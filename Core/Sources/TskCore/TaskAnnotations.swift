import Foundation

public struct TaskAnnotation: Identifiable, Equatable, Sendable {
    public let reference: UTF8String
    public let entry: Date?
    public let text: String
    public var id: UTF8String { reference }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.reference == rhs.reference && lhs.entry == rhs.entry && lhs.text.matchesBytes(rhs.text)
    }
}

public extension TaskRecord {
    var annotations: [TaskAnnotation] {
        attributes.compactMap { key, text in
            guard key.utf8.starts(with: "annotation_".utf8) else { return nil }
            let rawTimestamp = String(decoding: key.utf8.dropFirst(11), as: UTF8.self)
            let entry = Int64(rawTimestamp).map { Date(timeIntervalSince1970: Double($0)) }
            return TaskAnnotation(reference: UTF8String(key), entry: entry, text: text)
        }.sorted {
            if $0.entry != $1.entry { return ($0.entry ?? .distantFuture) < ($1.entry ?? .distantFuture) }
            return $0.reference < $1.reference
        }
    }
}

public extension TaskManager {
    func annotations(id: UUID) async throws -> [TaskAnnotation] { try await task(id: id).annotations }

    func addAnnotation(id: UUID, text: String) async throws -> TaskRecord {
        let lease = try await beginMutation()
        defer { endMutation(lease) }
        let source = try await task(id: id)
        guard source.canEdit else { throw TaskManagementError.unsupportedTaskKind }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TaskManagementError.emptyAnnotation }
        let instant = now().timeIntervalSince1970
        guard instant.isFinite, let initialTimestamp = Int64(exactly: instant.rounded(.towardZero)) else { throw TaskManagementError.invalidAnnotationTimestamp }
        var timestamp = initialTimestamp
        while source.attributes["annotation_\(timestamp)"] != nil {
            let next = timestamp.addingReportingOverflow(1)
            guard !next.overflow else { throw TaskManagementError.invalidAnnotationTimestamp }
            timestamp = next.partialValue
        }
        let saved = try await replica.update(id: id, changes: ["annotation_\(timestamp)": text, "modified": String(initialTimestamp)])
        localChangeWasCommitted()
        return saved
    }
}

public extension TaskManager {
    func editAnnotation(id: UUID, reference: String, text: String) async throws -> TaskRecord {
        let lease = try await beginMutation()
        defer { endMutation(lease) }
        let source = try await task(id: id)
        guard source.canEdit else { throw TaskManagementError.unsupportedTaskKind }
        guard reference.utf8.starts(with: "annotation_".utf8), source.attributes[reference] != nil else { throw TaskManagementError.annotationNotFound(reference) }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TaskManagementError.emptyAnnotation }
        if source.attributes[reference]?.matchesBytes(text) == true { return source }
        let saved = try await replica.update(id: id, changes: [reference: text, "modified": String(Int(now().timeIntervalSince1970))])
        localChangeWasCommitted()
        return saved
    }
}
