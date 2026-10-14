import Foundation

enum FilterVirtualTag: String, CaseIterable, Sendable {
    case blocked = "BLOCKED", unblocked = "UNBLOCKED", blocking = "BLOCKING", ready = "READY"
    case due = "DUE", dueToday = "DUETODAY", today = "TODAY", yesterday = "YESTERDAY", tomorrow = "TOMORROW", overdue = "OVERDUE"
    case week = "WEEK", month = "MONTH", quarter = "QUARTER", year = "YEAR"
    case active = "ACTIVE", scheduled = "SCHEDULED", child = "CHILD", instance = "INSTANCE", until = "UNTIL"
    case annotated = "ANNOTATED", tagged = "TAGGED", parent = "PARENT", template = "TEMPLATE"
    case waiting = "WAITING", pending = "PENDING", completed = "COMPLETED", deleted = "DELETED"
    case project = "PROJECT", priority = "PRIORITY", uda = "UDA", orphan = "ORPHAN"

    static func isWaiting(_ task: TaskRecord, at now: Date) -> Bool {
        task.status == "pending" && (FilterDateExpression.storedDate(task.attributes["wait"]) ?? .distantPast) > now
    }

    func includes(_ task: TaskRecord, context: TaskFilterContext) throws -> Bool {
        let availability = task.availability(at: context.now, tasks: context.tasks)
        let waiting = Self.isWaiting(task, at: context.now)
        let terminal = task.status == "completed" || task.status == "deleted"
        switch self {
        case .blocked: return availability.isBlocked
        case .unblocked: return !availability.isBlocked
        case .blocking:
            return !terminal && context.tasks.contains { source in
                source.status != "completed" && source.status != "deleted" && source.dependencyReferences.contains(task.id.uuidString.lowercased())
            }
        case .ready:
            return task.status == "pending" && !waiting && !availability.isBlocked &&
                (task.attributes["scheduled"] == nil || (FilterDateExpression.storedDate(task.attributes["scheduled"]) ?? Date(timeIntervalSince1970: 0)) < context.now)
        case .active: return task.attributes["start"] != nil
        case .scheduled: return task.attributes["scheduled"] != nil
        case .child, .instance: return task.attributes["parent"] != nil || task.attributes["template"] != nil
        case .until: return task.attributes["until"] != nil
        case .annotated: return task.attributes.keys.contains { $0.utf8.starts(with: "annotation_".utf8) }
        case .tagged: return task.attributes.keys.contains { $0.utf8.starts(with: "tag_".utf8) }
        case .parent, .template: return task.attributes["mask"] != nil || task.attributes["last"] != nil
        case .waiting: return waiting
        case .pending: return task.status == "pending" && !waiting
        case .completed: return task.status == "completed"
        case .deleted: return task.status == "deleted"
        case .project: return task.attributes["project"] != nil
        case .priority: return task.attributes["priority"] != nil
        case .uda:
            return task.attributes.keys.contains { context.schema.isUserDefined($0) }
        case .orphan:
            return task.attributes.keys.contains { key in
                !context.schema.contains(key)
            }
        default:
            guard !terminal, let due = FilterDateExpression.storedDate(task.attributes["due"]), due.timeIntervalSince1970 > 0 else { return false }
            let calendar = context.calendar
            let day = calendar.startOfDay(for: context.now)
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: day)!
            switch self {
            case .due: return due >= day && due < day.addingTimeInterval(7 * 86400)
            case .today, .dueToday: return due >= day && due < tomorrow
            case .yesterday: return due >= calendar.date(byAdding: .day, value: -1, to: day)! && due < day
            case .tomorrow: return due >= tomorrow && due < calendar.date(byAdding: .day, value: 1, to: tomorrow)!
            case .overdue: return task.status != "recurring" && due < context.now
            case .week, .month, .quarter, .year:
                let suffix = self == .week ? "w" : self == .month ? "m" : self == .quarter ? "q" : "y"
                return due >= FilterDateExpression.period("so" + suffix, context: context) && due <= FilterDateExpression.period("eo" + suffix, context: context)
            default: return false
            }
        }
    }
}
