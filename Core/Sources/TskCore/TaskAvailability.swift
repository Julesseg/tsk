import Foundation

public enum TaskUnavailabilityReason: Equatable, Sendable {
    case waiting(until: Date)
    case blocked(by: [TaskRecord])
}

public struct TaskAvailability: Equatable, Sendable {
    public let status: String
    public let reasons: [TaskUnavailabilityReason]
    public let diagnostics: [TaskDependencyLink]
    public var isAvailable: Bool { status == "pending" && reasons.isEmpty }
    public var isBlocked: Bool {
        reasons.contains { if case .blocked = $0 { true } else { false } }
    }
    public var isWaiting: Bool {
        reasons.contains { if case .waiting = $0 { true } else { false } }
    }
}

public extension TaskRecord {
    func availability(at now: Date, tasks: [TaskRecord] = []) -> TaskAvailability {
        var reasons: [TaskUnavailabilityReason]
        if status == "pending", let date = waitUntil, date > now {
            reasons = [.waiting(until: date)]
        } else {
            reasons = []
        }
        let links = dependencyLinks(in: tasks)
        let blockers = links.compactMap(\.task).filter { $0.status != "completed" && $0.status != "deleted" }
        if status != "completed", status != "deleted", !blockers.isEmpty { reasons.append(.blocked(by: blockers)) }
        return TaskAvailability(status: status, reasons: reasons, diagnostics: links.filter { $0.issue != nil })
    }
}
