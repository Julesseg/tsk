import Foundation

public struct TaskSeriesTransitionDefaults: Sendable {
    public let effectiveDate: Date
    public let firstDue: Date
    public let recurrence: String
    public let planned: Date
    public let wait: Date
    public let hasUntil: Bool
    public let until: Date

    public init(template: TaskRecord, tasks: [TaskRecord], now: Date) {
        effectiveDate = now
        firstDue = tasks.filter { UUID(uuidString: $0.attributes["parent"] ?? "") == template.id && $0.status == "pending" }
            .compactMap(\.deadline).filter { $0 >= now }.min() ?? now.addingTimeInterval(86400)
        recurrence = template.attributes["recur"] ?? "weekly"
        let anchor = template.deadline ?? firstDue
        planned = firstDue.addingTimeInterval((template.plannedDate ?? firstDue).timeIntervalSince(anchor))
        wait = firstDue.addingTimeInterval((template.waitUntil ?? firstDue).timeIntervalSince(anchor))
        hasUntil = template.attributes["until"] != nil
        until = template.attributes["until"].flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:)) ?? firstDue.addingTimeInterval(31536000)
    }
}

extension TaskSeriesOffsetChange {
    public static func setting(date: Date, relativeTo due: Date) throws -> Self {
        guard let seconds = Int64(exactly: date.timeIntervalSince(due).rounded(.towardZero)) else { throw TaskSeriesTransitionError.invalidDate }
        return .set(seconds)
    }
}
