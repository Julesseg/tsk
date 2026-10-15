import Foundation

public protocol TaskAtomicSnapshotMutatingReplica: TaskAtomicMutatingReplica {
    func updateAtomically(_ updates: [TaskAtomicUpdate], expecting records: [TaskRecord]) async throws -> [TaskRecord]
}

public struct TaskSeriesMetadataPreview: Sendable {
    public let template: TaskRecord
    public let affected: [TaskRecord]
    public let cutoff: Date
    public let updates: [TaskAtomicUpdate]
    let snapshot: [TaskRecord]
    let definitions: [TaskAttributeDefinition]
}

public enum TaskSeriesMetadataError: Error, LocalizedError, Sendable {
    case stalePreview
    case invalidSeries
    case unsupportedField(String)

    public var errorDescription: String? {
        switch self {
        case .stalePreview: "Tasks or attribute definitions changed after this preview. Preview the series again before saving."
        case .invalidSeries: "The series contains inconsistent links, dates, or bookkeeping. No tasks were changed."
        case .unsupportedField(let name): "The \(name) field is not part of series metadata. Use its dedicated action."
        }
    }
}

extension TaskManager {
    public func previewSeriesMetadata(id: UUID, changes: TaskAttributePatch, addingAnnotation: String = "") async throws -> TaskSeriesMetadataPreview {
        let lease = try await beginMutation()
        defer { endMutation(lease) }
        let snapshot = try await replica.tasks().sorted { $0.id.uuidString < $1.id.uuidString }
        guard let template = snapshot.first(where: { $0.id == id }) else { throw TaskManagementError.taskNotFound(id) }
        guard template.status == "recurring", template.attributes["parent"] == nil else { throw TaskManagementError.unsupportedTaskKind }
        let cutoff = now()
        let definitions = try await userAttributeDefinitions?.load() ?? []
        let defined = Set(definitions.map(\.name))
        var patch = changes
        for (key, value) in changes {
            if ["description", "project", "priority"].contains(key) || key.utf8.starts(with: "tag_".utf8) { continue }
            if key.utf8.starts(with: "annotation_".utf8) {
                guard template.attributes[key] != nil, let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TaskManagementError.emptyAnnotation }
            } else if TaskFilterSchema.standard.contains(key) || key.utf8.starts(with: "dep_".utf8) || !defined.contains(UTF8String(key)) { throw TaskSeriesMetadataError.unsupportedField(key) }
        }
        if changes.keys.contains("description") {
            let text = (changes["description"] ?? nil)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { throw TaskManagementError.emptyDescription }
            patch["description"] = text
        }
        patch = try await normalizedUserAttributes(patch)
        let children = snapshot.filter { UUID(uuidString: $0.attributes["parent"] ?? "") == id }
        var affected: [TaskRecord] = []
        let mask = template.attributes["mask"].map { Array($0.utf8) }
        if let mask, !mask.allSatisfy({ [45, 87, 43, 88].contains($0) }) { throw TaskSeriesMetadataError.invalidSeries }
        var positions = Set<Int>()
        for child in children {
            guard let raw = child.attributes["imask"], !raw.isEmpty, raw.utf8.allSatisfy({ (48...57).contains($0) }), let index = Int(raw),
                  let mask, index < mask.count, positions.insert(index).inserted else { throw TaskSeriesMetadataError.invalidSeries }
            switch child.status {
            case "pending":
                guard [45, 87].contains(mask[index]), let due = child.deadline else { throw TaskSeriesMetadataError.invalidSeries }
                if due >= cutoff { affected.append(child) }
            case "completed": guard mask[index] == 43 else { throw TaskSeriesMetadataError.invalidSeries }
            case "deleted": guard mask[index] == 88 else { throw TaskSeriesMetadataError.invalidSeries }
            default: throw TaskSeriesMetadataError.invalidSeries
            }
        }
        affected.sort { ($0.deadline ?? .distantFuture, $0.id.uuidString) < ($1.deadline ?? .distantFuture, $1.id.uuidString) }
        if !addingAnnotation.isEmpty {
            guard !addingAnnotation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TaskManagementError.emptyAnnotation }
            guard let initial = Int64(exactly: cutoff.timeIntervalSince1970.rounded(.towardZero)) else { throw TaskManagementError.invalidAnnotationTimestamp }
            var timestamp = initial
            while ([template] + children).contains(where: { $0.attributes["annotation_\(timestamp)"] != nil }) {
                let next = timestamp.addingReportingOverflow(1)
                guard !next.overflow else { throw TaskManagementError.invalidAnnotationTimestamp }
                timestamp = next.partialValue
            }
            patch["annotation_\(timestamp)"] = addingAnnotation
        }
        let updates = try ([template] + affected).map { record in
            var normalized = try TaskOrganization.normalizedChanges(patch, original: record.attributes)
            for (key, value) in normalized where value.matchesBytes(record.attributes[key]) { normalized.removeValue(forKey: key) }
            if !normalized.isEmpty { normalized["modified"] = String(Int(cutoff.timeIntervalSince1970)) }
            return TaskAtomicUpdate(id: record.id, expected: record.attributes, changes: normalized)
        }
        return TaskSeriesMetadataPreview(template: template, affected: affected, cutoff: cutoff, updates: updates, snapshot: snapshot, definitions: definitions)
    }

    public func applySeriesMetadata(_ preview: TaskSeriesMetadataPreview) async throws -> TaskRecord {
        let lease = try await beginMutation()
        defer { endMutation(lease) }
        let current = try await replica.tasks().sorted { $0.id.uuidString < $1.id.uuidString }
        guard current == preview.snapshot, try await userAttributeDefinitions?.load() ?? [] == preview.definitions else { throw TaskSeriesMetadataError.stalePreview }
        guard preview.affected.allSatisfy({ ($0.deadline ?? .distantPast) >= now() }) else { throw TaskSeriesMetadataError.stalePreview }
        guard preview.updates.contains(where: { !$0.changes.isEmpty }) else { return preview.template }
        guard let atomic = replica as? any TaskAtomicSnapshotMutatingReplica else { throw TaskManagementError.storage("This adapter cannot save a series against its complete preview snapshot.") }
        let saved = try await atomic.updateAtomically(preview.updates, expecting: preview.snapshot)
        guard let template = saved.first(where: { $0.id == preview.template.id }) else { throw TaskManagementError.storage("The atomic series save returned no template.") }
        localChangeWasCommitted()
        return template
    }
}
