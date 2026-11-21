import Foundation

extension TaskDateRole {
    var attribute: String {
        switch self { case .planned: "scheduled"; case .deadline: "due" }
    }
}

public enum TaskReschedulingError: Error, Equatable, LocalizedError, Sendable {
    case invalidDate, pastUntimedScheduledDate
    public var errorDescription: String? {
        switch self {
        case .invalidDate: "Choose a valid Scheduled date and time or Deadline."
        case .pastUntimedScheduledDate: "Choose today or a future day, or add a time to schedule in the past."
        }
    }
}

extension TaskManager {
    func validateScheduled(_ intent: TaskScheduledDate?, at instant: Date) throws {
        guard let intent, !intent.hasTime else { return }
        if intent.date < calendar.startOfDay(for: instant) { throw TaskReschedulingError.pastUntimedScheduledDate }
    }

    func validateScheduledChange(_ patch: TaskAttributePatch, original: TaskAttributes, at instant: Date) throws {
        guard patch.keys.contains("scheduled") || patch.keys.contains(TaskScheduledDate.attribute) else { return }
        var attributes = original
        for key in ["scheduled", TaskScheduledDate.attribute] {
            if let value = patch[key] { attributes[key] = value }
        }
        guard attributes["scheduled"] != original["scheduled"] || attributes[TaskScheduledDate.attribute] != original[TaskScheduledDate.attribute] else { return }
        try validateScheduled(TaskScheduledDate.read(from: attributes, calendar: calendar), at: instant)
    }

    public func reschedule(id: UUID, role: TaskDateRole, to date: Date?) async throws -> TaskRecord {
        if let date {
            guard date.timeIntervalSince1970.isFinite, abs(date.timeIntervalSince1970) <= 253402300799 else { throw TaskReschedulingError.invalidDate }
        }
        var changes: TaskAttributePatch = [:]
        changes.updateValue(date.map { String(Int($0.timeIntervalSince1970)) }, forKey: role.attribute)
        return try await update(id: id, changes: changes)
    }
}
