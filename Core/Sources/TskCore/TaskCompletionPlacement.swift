import Foundation

internal enum TaskCompletionPlacement {
    static let attribute = "tsk_completion_page"

    static func dayKey(_ day: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.era, .year, .month, .day], from: day)
        return "v1:\(parts.era ?? 1):\(parts.year ?? 0):\(parts.month ?? 0):\(parts.day ?? 0)"
    }

    static func page(for task: TaskRecord, at instant: Date, calendar: Calendar) -> String? {
        guard let date = task.plannerDate(calendar: calendar)?.date else { return nil }
        return dayKey(max(calendar.startOfDay(for: date), calendar.startOfDay(for: instant)), calendar: calendar)
    }

    static func includes(_ task: TaskRecord, day: Date, calendar: Calendar) -> Bool {
        let key = dayKey(day, calendar: calendar)
        if let stored = task.attributes[attribute], stored.hasPrefix("v1:") {
            let parts = stored.split(separator: ":", omittingEmptySubsequences: false)
            if parts.count == 5,
               let era = Int(parts[1]), (0...1).contains(era),
               let year = Int(parts[2]), (1...9999).contains(year),
               let month = Int(parts[3]), (1...13).contains(month),
               let day = Int(parts[4]), (1...31).contains(day),
               let date = calendar.date(from: DateComponents(era: era, year: year, month: month, day: day)),
               dayKey(date, calendar: calendar) == stored { return stored == key }
        }
        guard let end = planningDate(task.attributes["end"]) else { return false }
        return page(for: task, at: end, calendar: calendar) == key
    }
}

extension TaskManager {
    func completionChanges(for task: TaskRecord, at instant: Date) -> TaskAttributePatch {
        let timestamp = String(Int(instant.timeIntervalSince1970))
        var patch: TaskAttributePatch = ["status": "completed", "end": task.attributes["end"] ?? timestamp,
                                        "modified": timestamp, "start": nil]
        patch.updateValue(TaskCompletionPlacement.page(for: task, at: instant, calendar: calendar), forKey: TaskCompletionPlacement.attribute)
        return patch
    }
}
