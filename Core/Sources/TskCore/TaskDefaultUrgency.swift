import Foundation

enum TaskDefaultUrgency {
    static func value(for task: TaskRecord, context: TaskFilterContext) -> Double {
        var value: Float = 0
        value += task.attributes["project"] != nil ? 1 : 0
        value += task.attributes["start"] != nil ? 4 : 0
        value += task.attributes["scheduled"] != nil && epoch(task.attributes["scheduled"]) < context.now.timeIntervalSince1970 ? 5 : 0
        value += FilterVirtualTag.isWaiting(task, at: context.now) ? -3 : 0
        value += task.availability(at: context.now, tasks: context.tasks).isBlocked ? -5 : 0
        value += countFactor(task.attributes.keys.filter { $0.utf8.starts(with: "annotation_".utf8) }.count)
        value += countFactor(task.attributes.keys.filter { $0.utf8.starts(with: "tag_".utf8) }.count)
        if let due = task.attributes["due"] {
            let daysOverdue = Float((context.now.timeIntervalSince1970 - epoch(due)) / 86400)
            let factor: Float
            if daysOverdue >= 7 { factor = 1 }
            else if daysOverdue >= -14 { factor = Float(((Double(daysOverdue) + 14) * 0.8 / 21) + 0.2) }
            else { factor = 0.2 }
            value += factor * 12
        }
        let terminal = task.status == "completed" || task.status == "deleted"
        let blocking = !terminal && context.tasks.contains { source in
            source.status != "completed" && source.status != "deleted" && source.dependencyReferences.contains(task.id.uuidString.lowercased())
        }
        value += blocking ? 8 : 0
        if let entry = task.attributes["entry"] {
            let age = ((context.now.timeIntervalSince1970 - epoch(entry)) / 86400).rounded(.towardZero)
            value += (age > 365 ? 1 : Float(age / 365)) * 2
        } else { value += 2 }
        switch task.attributes["priority"] {
        case "H": value += 6
        case "M": value += 3.9
        case "L": value += 1.8
        default: break
        }
        if task.attributes["tag_next"] != nil { value += 15 }
        return Double(value)
    }

    private static func epoch(_ raw: String?) -> TimeInterval {
        FilterDateExpression.storedDate(raw)?.timeIntervalSince1970 ?? 0
    }

    private static func countFactor(_ count: Int) -> Float {
        switch count {
        case 0: 0
        case 1: 0.8
        case 2: 0.9
        default: 1
        }
    }
}
