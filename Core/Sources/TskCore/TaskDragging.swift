import Foundation

public enum TaskDragContext: Equatable, Sendable {
    case day(Date)
    case project(String)

    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.day(let left), .day(let right)): left == right
        case (.project(let left), .project(let right)): left.matchesBytes(right)
        default: false
        }
    }
}

public enum TaskDragDirection: Equatable, Sendable {
    case upward, downward
}

public struct TaskDragSession: Sendable {
    public private(set) var tasks: [TaskRecord]
    public let ids: [UUID]
    public let context: TaskDragContext
    public private(set) var lastCrossedID: UUID?
    public private(set) var lastCrossedEventID: CalendarEventIdentity?
    let originals: [TaskRecord]
    let calendar: Calendar

    public init(tasks: [TaskRecord], ids: [UUID], context: TaskDragContext, calendar: Calendar = .autoupdatingCurrent) throws {
        let selected = Set(ids)
        guard Set(tasks.map(\.id)).count == tasks.count, !selected.isEmpty, selected.count == ids.count,
              selected.isSubset(of: Set(tasks.filter(\.canComplete).map(\.id))) else {
            throw TaskManagementError.unsupportedTaskKind
        }
        self.tasks = tasks
        originals = tasks
        self.ids = tasks.filter { selected.contains($0.id) }.map(\.id)
        self.context = context
        self.calendar = calendar
    }

    public mutating func cross(_ id: UUID, direction: TaskDragDirection? = nil) {
        let ids = ids
        let calendar = calendar
        guard !ids.contains(id), let target = originals.first(where: { $0.id == id }),
              let destination = tasks.firstIndex(where: { $0.id == id }),
              let source = tasks.firstIndex(where: { ids.contains($0.id) }) else { return }
        if case .day = context, target.plannerDate(calendar: calendar) == nil { return }
        lastCrossedEventID = nil
        lastCrossedID = id
        var moving = tasks.filter { ids.contains($0.id) }
        if case .day = context, let intent = target.plannerDate(calendar: calendar) {
            moving = moving.map { task in
                var copy = task
                var draft = TaskDraft(attributes: task.attributes)
                draft.setScheduled(intent)
                copy.attributes = draft.attributes
                return copy
            }
        }
        tasks.removeAll { ids.contains($0.id) }
        let index = tasks.firstIndex(where: { $0.id == id })!
        let followsTarget = direction == .downward || (direction == nil && source < destination)
        tasks.insert(contentsOf: moving, at: index + (followsTarget ? 1 : 0))
        constrainDayOrder()
    }

    public mutating func cross(_ event: CalendarEventSnapshot) {
        guard case .day = context, !event.isAllDay, !event.isCanceled,
              event.start.timeIntervalSince1970.isFinite, event.end >= event.start,
              abs(event.start.timeIntervalSince1970) <= 253402300799,
              !event.calendarID.isEmpty, !event.eventID.isEmpty else { return }
        lastCrossedID = nil
        lastCrossedEventID = event.id
        let selected = Set(ids)
        var moving = tasks.filter { selected.contains($0.id) }
        moving = moving.map { task in
            var copy = task
            var draft = TaskDraft(attributes: task.attributes)
            draft.setScheduled(TaskScheduledDate(date: event.start, hasTime: true))
            copy.attributes = draft.attributes
            return copy
        }
        tasks.removeAll { selected.contains($0.id) }
        tasks.append(contentsOf: moving)
        constrainDayOrder()
    }

    private mutating func constrainDayOrder() {
        guard case .day(let date) = context else { return }
        let day = calendar.startOfDay(for: date)
        let positions = Dictionary(uniqueKeysWithValues: tasks.enumerated().map { ($0.element.id, $0.offset) })
        let calendar = calendar
        tasks.sort {
            if TaskPlannerOrder.groupPrecedes($0, $1, on: day, calendar: calendar) { return true }
            if TaskPlannerOrder.groupPrecedes($1, $0, on: day, calendar: calendar) { return false }
            return positions[$0.id]! < positions[$1.id]!
        }
    }
}

internal enum TaskManualOrder {
    static let plannerAttribute = "tsk_planner_order"
    static let projectAttribute = "tsk_project_order"

    static func plannerGroup(_ task: TaskRecord, calendar: Calendar) -> String? {
        guard let intent = task.plannerDate(calendar: calendar) else { return nil }
        let day = Int(calendar.startOfDay(for: intent.date).timeIntervalSince1970)
        let key = "\(day):\(intent.hasTime ? String(Int(intent.date.timeIntervalSince1970)) : "untimed")"
        return task.plannedDate == nil ? "deadline:" + key : key
    }

    static func value(group: String, rank: Int) -> String {
        "v1:\(Data(group.utf8).base64EncodedString()):\(rank)"
    }

    static func rank(_ task: TaskRecord, attribute: String, group: String) -> Int? {
        guard let value = task.attributes[attribute] else { return nil }
        let keys = group.hasPrefix("deadline:") && attribute == plannerAttribute ? [group, String(group.dropFirst("deadline:".count))] : [group]
        for key in keys {
            let prefix = "v1:\(Data(key.utf8).base64EncodedString()):"
            if value.hasPrefix(prefix), let rank = Int(value.dropFirst(prefix.count)), rank >= 0 { return rank }
        }
        return nil
    }

    static func precedes(_ lhs: TaskRecord, _ rhs: TaskRecord, attribute: String, group: String) -> Bool? {
        let left = rank(lhs, attribute: attribute, group: group)
        let right = rank(rhs, attribute: attribute, group: group)
        if left == right { return nil }
        switch (left, right) {
        case (.some(let left), .some(let right)): return left < right
        case (.some, .none): return true
        case (.none, .some): return false
        case (.none, .none): return nil
        }
    }
}

extension TaskManager {
    public func drop(_ drag: TaskDragSession) async throws -> [TaskRecord] {
        let lease = try await beginMutation()
        defer { endMutation(lease) }
        guard drag.lastCrossedID != nil || drag.lastCrossedEventID != nil else { return [] }
        let records = try await replica.tasks()
        guard drag.originals.allSatisfy({ original in records.first { $0.id == original.id } == original }) else {
            throw TaskManagementError.storage("Tasks changed during the drag. No tasks were changed.")
        }
        let ordered: [TaskRecord]
        switch drag.context {
        case .day(let day):
            guard drag.originals.allSatisfy({ $0.isOnDay(day, at: now(), calendar: calendar) }) else {
                throw TaskManagementError.storage("The day page changed during the drag. No tasks were changed.")
            }
            ordered = drag.tasks
        case .project(let name):
            guard drag.originals.allSatisfy({ $0.project.matchesBytes(name) && $0.status == "pending" }) else {
                throw TaskManagementError.storage("The project changed during the drag. No tasks were changed.")
            }
            ordered = drag.tasks
        }
        return try await saveOrder(ordered, context: drag.context, records: records)
    }

    func saveOrder(_ ordered: [TaskRecord], context: TaskDragContext, records: [TaskRecord], creating: TaskRecord? = nil) async throws -> [TaskRecord] {
        var ranks: [String: Int] = [:]
        var updates: [TaskAtomicUpdate] = []
        var parents: [UUID: TaskRecord] = [:]
        let timestamp = String(Int(now().timeIntervalSince1970))
        var created = creating
        for var task in ordered {
            let attribute: String
            let group: String
            switch context {
            case .day:
                guard let key = TaskManualOrder.plannerGroup(task, calendar: calendar) else { continue }
                attribute = TaskManualOrder.plannerAttribute
                group = key
            case .project(let name):
                attribute = TaskManualOrder.projectAttribute
                group = name
            }
            let rank = ranks[group, default: 0]
            ranks[group] = rank + 1
            task.attributes[attribute] = TaskManualOrder.value(group: group, rank: rank)
            if task.id == creating?.id {
                created = task
                continue
            }
            guard let original = records.first(where: { $0.id == task.id }) else { throw TaskManagementError.taskNotFound(task.id) }
            var patch = task.attributes.changes(comparedTo: original.attributes)
            guard !patch.isEmpty else { continue }
            let retainedHistory = task.status == "completed" && patch.keys.allSatisfy { $0 == attribute }
            guard task.canComplete || retainedHistory else { throw TaskManagementError.unsupportedTaskKind }
            if task.isOccurrence && !retainedHistory {
                let (parent, index) = try occurrencePosition(original, in: records)
                let byte = try occurrenceMutationMask(original, changes: patch, parent: parent, index: index, completing: false)
                var updated = parents[parent.id] ?? parent
                var mask = Array(updated.attributes["mask"]!.utf8)
                mask[index] = byte
                updated.attributes["mask"] = String(decoding: mask, as: UTF8.self)
                parents[parent.id] = updated
            }
            patch["modified"] = timestamp
            updates.append(TaskAtomicUpdate(id: task.id, expected: original.attributes, changes: patch))
        }
        for parent in parents.values.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            let original = records.first { $0.id == parent.id }!
            if parent.attributes != original.attributes {
                updates.append(TaskAtomicUpdate(id: parent.id, expected: original.attributes, changes: ["mask": parent.attributes["mask"], "modified": timestamp]))
            }
        }
        if let created {
            let saved: [TaskRecord]
            if updates.isEmpty {
                saved = [try await replica.create(id: created.id, attributes: created.attributes)]
            } else {
                guard let atomic = replica as? any TaskAtomicTransitionReplica else {
                    throw TaskManagementError.storage("This storage adapter cannot save incoming task order atomically. No tasks were changed.")
                }
                saved = try await atomic.commitAtomically(creating: [.init(id: created.id, attributes: created.attributes)], updating: updates, expecting: records)
            }
            await localChangeWasCommitted(tasks: saved)
            return ordered.map { task in saved.first { $0.id == task.id } ?? task }
        }
        guard !updates.isEmpty else { return ordered }
        guard let atomic = replica as? any TaskAtomicSnapshotMutatingReplica else {
            throw TaskManagementError.storage("This storage adapter cannot save task order atomically. No tasks were changed.")
        }
        let saved = try await atomic.updateAtomically(updates, expecting: records)
        await localChangeWasCommitted(tasks: saved)
        return ordered.map { task in saved.first { $0.id == task.id } ?? task }
    }
}

public enum TaskSchedulingChange: Equatable, Sendable {
    case day(Date)
    case intent(TaskScheduledDate)
}

extension TaskManager {
    func appendingIncoming(_ incoming: [TaskRecord], to records: [TaskRecord]) -> [TaskRecord] {
        let seen = Set(incoming.map(\.id))
        let groups = Set(incoming.compactMap { TaskManualOrder.plannerGroup($0, calendar: calendar) })
        let instant = now()
        let day = calendar.startOfDay(for: instant)
        let destination = records.filter { task in
            let retainedHistory = task.status == "completed" && task.plannerDate(calendar: calendar).map {
                task.isOnDay(max(instant, $0.date), at: instant, calendar: calendar)
            } == true
            return (task.canComplete || retainedHistory) && !seen.contains(task.id) && TaskManualOrder.plannerGroup(task, calendar: calendar).map { groups.contains($0) } == true
        }.sorted { TaskPlannerOrder.precedes($0, $1, on: day, calendar: calendar) }
        return destination + incoming
    }

    public func schedule(ids: [UUID], change: TaskSchedulingChange) async throws -> [TaskRecord] {
        let lease = try await beginMutation()
        defer { endMutation(lease) }
        let records = try await replica.tasks()
        var seen: Set<UUID> = []
        let ids = ids.filter { seen.insert($0).inserted }
        guard !ids.isEmpty else { return [] }
        let incoming = try ids.map { id -> TaskRecord in
            guard var task = records.first(where: { $0.id == id }) else { throw TaskManagementError.taskNotFound(id) }
            guard task.canComplete else { throw TaskManagementError.unsupportedTaskKind }
            let intent: TaskScheduledDate
            switch change {
            case .intent(let value): intent = value
            case .day(let day):
                guard day.timeIntervalSince1970.isFinite, abs(day.timeIntervalSince1970) <= 253402300799 else { throw TaskReschedulingError.invalidDate }
                let existing = task.plannerDate(calendar: calendar)
                guard let date = taskDate(on: day, keepingTimeFrom: existing?.date, calendar: calendar) else { throw TaskReschedulingError.invalidDate }
                intent = TaskScheduledDate(date: date, hasTime: existing?.hasTime ?? false)
            }
            let seconds = intent.date.timeIntervalSince1970
            guard seconds.isFinite, abs(seconds) <= 253402300799 else { throw TaskReschedulingError.invalidDate }
            var draft = TaskDraft(attributes: task.attributes)
            draft.setScheduled(intent)
            task.attributes = draft.attributes
            return task
        }
        let saved = try await saveOrder(appendingIncoming(incoming, to: records), context: .day(now()), records: records)
        return ids.compactMap { id in saved.first { $0.id == id } }
    }
}
