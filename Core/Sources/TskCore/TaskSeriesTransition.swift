import Foundation

public struct TaskAtomicCreate: Codable, Sendable {
    public let id: UUID
    public let attributes: TaskAttributes
    public init(id: UUID, attributes: TaskAttributes) { self.id = id; self.attributes = attributes }
}

public protocol TaskAtomicTransitionReplica: TaskAtomicSnapshotMutatingReplica {
    func commitAtomically(creating: [TaskAtomicCreate], updating: [TaskAtomicUpdate], expecting: [TaskRecord]) async throws -> [TaskRecord]
}

public enum TaskSeriesOffsetChange: Equatable, Sendable {
    case preserve, clear, set(Int64)
}

public struct TaskSeriesTransitionDraft: Sendable {
    public var effectiveDate: Date
    public var firstDue: Date
    public var recurrence: String
    public var generatorTimeZone: String
    public var planned: TaskSeriesOffsetChange
    public var wait: TaskSeriesOffsetChange
    public var until: Date?

    public init(effectiveDate: Date, firstDue: Date, recurrence: String, generatorTimeZone: String, planned: TaskSeriesOffsetChange = .preserve, wait: TaskSeriesOffsetChange = .preserve, until: Date? = nil) {
        self.effectiveDate = effectiveDate; self.firstDue = firstDue; self.recurrence = recurrence; self.generatorTimeZone = generatorTimeZone
        self.planned = planned; self.wait = wait; self.until = until
    }
}

public struct TaskSeriesTransitionPreview: Sendable {
    public let original: TaskRecord
    public let successor: TaskRecord
    public let affected: [TaskRecord]
    public let moved: [TaskRecord]
    public let effectiveDate: Date
    public let generatorTimeZone: String
    public let nextGeneratorDue: Date
    let snapshot: [TaskRecord]
    let updates: [TaskAtomicUpdate]
}

extension TaskManager {
    public func previewSeriesTransition(id: UUID, draft: TaskSeriesTransitionDraft) async throws -> TaskSeriesTransitionPreview {
        let lease = try await beginMutation()
        defer { endMutation(lease) }
        let instant = now()
        guard TaskRecurrenceSchedule.valid(draft.effectiveDate), TaskRecurrenceSchedule.valid(draft.firstDue),
              let firstSeconds = Int64(exactly: draft.firstDue.timeIntervalSince1970.rounded(.towardZero)) else { throw TaskSeriesTransitionError.invalidDate }
        let cutoff = max(draft.effectiveDate, instant)
        let first = Date(timeIntervalSince1970: Double(firstSeconds))
        guard first >= cutoff else { throw TaskSeriesTransitionError.invalidDate }
        let snapshot = try await replica.tasks().sorted { $0.id.uuidString < $1.id.uuidString }
        let series = try TaskSeriesRecords(records: snapshot, id: id, cutoff: cutoff)
        guard series.template.deadline != nil, series.template.attributes["rtype"] == nil || series.template.attributes["rtype"] == "periodic" else { throw TaskSeriesMetadataError.invalidSeries }
        try validateRetirementCoverage(series, cutoff: cutoff, timeZone: draft.generatorTimeZone)
        let schedule = try TaskRecurrenceSchedule(rule: draft.recurrence, timeZone: draft.generatorTimeZone)
        let dates = try schedule.dates(first: first, count: max(2, series.affected.count + 1))
        if let until = draft.until {
            guard TaskRecurrenceSchedule.valid(until), until >= first, series.affected.isEmpty || dates[series.affected.count - 1] <= until else { throw TaskSeriesTransitionError.untilBeforeRetainedOccurrence }
        }
        let timestamp = String(Int(instant.timeIntervalSince1970))
        let successorID = UUID()
        var attributes = series.template.attributes
        for key in ["uuid", "id", "parent", "imask", "mask", "end", "start"] { attributes.removeValue(forKey: key) }
        attributes["status"] = "recurring"; attributes["entry"] = timestamp; attributes["modified"] = timestamp
        attributes["due"] = String(firstSeconds); attributes["recur"] = schedule.rule.rawValue; attributes["rtype"] = "periodic"
        attributes["until"] = draft.until.map { String(Int($0.timeIntervalSince1970)) }
        attributes["scheduled"] = try shifted("scheduled", change: draft.planned, record: series.template, due: first)
        attributes["wait"] = try shifted("wait", change: draft.wait, record: series.template, due: first)
        var moved: [TaskRecord] = []
        var updates: [TaskAtomicUpdate] = []
        var oldMask = Array((series.template.attributes["mask"] ?? "").utf8)
        var newMask: [UInt8] = []
        for (position, original) in series.affected.enumerated() {
            var patch: TaskAttributePatch = ["parent": successorID.uuidString.lowercased(), "imask": String(position), "due": String(Int(dates[position].timeIntervalSince1970)), "recur": schedule.rule.rawValue, "rtype": "periodic", "modified": timestamp]
            patch.updateValue(try shifted("scheduled", change: draft.planned, record: original, due: dates[position]), forKey: "scheduled")
            patch.updateValue(try shifted("wait", change: draft.wait, record: original, due: dates[position]), forKey: "wait")
            patch.updateValue(attributes["until"], forKey: "until")
            var record = original
            for (key, value) in patch { record.attributes[key] = value }
            moved.append(record)
            updates.append(TaskAtomicUpdate(id: original.id, expected: original.attributes, changes: patch))
            oldMask[Int(original.attributes["imask"]!)!] = 88
            newMask.append((record.waitUntil ?? .distantPast) > instant ? 87 : 45)
        }
        if !newMask.isEmpty { attributes["mask"] = String(decoding: newMask, as: UTF8.self) }
        var retirement: TaskAttributePatch = ["status": "deleted", "end": timestamp, "modified": timestamp]
        if series.template.attributes["mask"] != nil { retirement["mask"] = String(decoding: oldMask, as: UTF8.self) }
        updates.insert(TaskAtomicUpdate(id: id, expected: series.template.attributes, changes: retirement), at: 0)
        return TaskSeriesTransitionPreview(original: series.template, successor: TaskRecord(id: successorID, attributes: attributes), affected: series.affected, moved: moved, effectiveDate: cutoff, generatorTimeZone: draft.generatorTimeZone, nextGeneratorDue: dates[series.affected.count], snapshot: snapshot, updates: updates)
    }

    public func applySeriesTransition(_ preview: TaskSeriesTransitionPreview) async throws -> TaskRecord {
        let lease = try await beginMutation()
        defer { endMutation(lease) }
        guard try await replica.tasks().sorted(by: { $0.id.uuidString < $1.id.uuidString }) == preview.snapshot,
              preview.affected.allSatisfy({ ($0.deadline ?? .distantPast) >= now() }), preview.successor.deadline.map({ $0 >= now() }) == true else { throw TaskSeriesMetadataError.stalePreview }
        guard let atomic = replica as? any TaskAtomicTransitionReplica else { throw TaskManagementError.storage("This adapter cannot create and update a series in one transaction.") }
        let result = try await atomic.commitAtomically(creating: [TaskAtomicCreate(id: preview.successor.id, attributes: preview.successor.attributes)], updating: preview.updates, expecting: preview.snapshot)
        guard let successor = result.first(where: { $0.id == preview.successor.id }) else { throw TaskManagementError.storage("The atomic transition returned no successor template.") }
        localChangeWasCommitted()
        return successor
    }

    private func validateRetirementCoverage(_ series: TaskSeriesRecords, cutoff: Date, timeZone: String) throws {
        let mask = Array((series.template.attributes["mask"] ?? "").utf8)
        let positions = Set(series.children.compactMap { $0.attributes["imask"].flatMap(Int.init) })
        guard mask.enumerated().allSatisfy({ [43, 88].contains($0.element) || positions.contains($0.offset) }),
              let first = series.template.deadline, let rule = series.template.attributes["recur"] else { throw TaskSeriesTransitionError.incompleteGeneratorHorizon }
        let schedule = try TaskRecurrenceSchedule(rule: rule, timeZone: timeZone)
        let dates = try schedule.dates(first: first, count: mask.count + 1)
        if let raw = series.template.attributes["until"] {
            guard let seconds = TimeInterval(raw), seconds.isFinite else { throw TaskSeriesMetadataError.invalidSeries }
            if mask.count > 0, dates[mask.count - 1].timeIntervalSince1970 > seconds { return }
        }
        guard dates[mask.count] >= cutoff else { throw TaskSeriesTransitionError.incompleteGeneratorHorizon }
    }

    private func shifted(_ key: String, change: TaskSeriesOffsetChange, record: TaskRecord, due: Date) throws -> String? {
        let offset: Int64
        switch change {
        case .clear: return nil
        case .set(let seconds): offset = seconds
        case .preserve:
            guard let raw = record.attributes[key] else { return nil }
            guard let value = Int64(raw), let oldDue = record.attributes["due"].flatMap(Int64.init) else { throw TaskSeriesTransitionError.invalidOffset }
            let difference = value.subtractingReportingOverflow(oldDue)
            guard !difference.overflow else { throw TaskSeriesTransitionError.invalidOffset }
            offset = difference.partialValue
        }
        let result = due.timeIntervalSince1970 + Double(offset)
        guard result.isFinite, result > 0, result <= 253402300799, let seconds = Int64(exactly: result) else { throw TaskSeriesTransitionError.invalidOffset }
        return String(seconds)
    }
}

extension TaskRecord {
    public var isRetiredRecurringTemplate: Bool { status == "deleted" && attributes["parent"] == nil && attributes["recur"] != nil }
}
