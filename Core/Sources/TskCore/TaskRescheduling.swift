import Foundation

extension TaskDateRole {
    var attribute: String {
        switch self { case .planned: "scheduled"; case .deadline: "due" }
    }
}

public enum TaskReschedulingError: Error, Equatable, LocalizedError, Sendable {
    case invalidDate
    public var errorDescription: String? { "Choose a valid planned day or deadline." }
}

extension TaskManager {
    public func reschedule(id: UUID, role: TaskDateRole, to date: Date?) async throws -> TaskRecord {
        if let date {
            guard date.timeIntervalSince1970.isFinite, abs(date.timeIntervalSince1970) <= 253402300799 else { throw TaskReschedulingError.invalidDate }
        }
        var changes: TaskAttributePatch = [:]
        changes.updateValue(date.map { String(Int($0.timeIntervalSince1970)) }, forKey: role.attribute)
        return try await update(id: id, changes: changes)
    }
}
