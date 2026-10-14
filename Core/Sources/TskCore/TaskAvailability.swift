import Foundation

public enum TaskUnavailabilityReason: Equatable, Sendable {
    case waiting(until: Date)
}

public struct TaskAvailability: Equatable, Sendable {
    public let status: String
    public let reasons: [TaskUnavailabilityReason]
    public var isAvailable: Bool { status == "pending" && reasons.isEmpty }
    public var isWaiting: Bool {
        reasons.contains { if case .waiting = $0 { true } else { false } }
    }
}

public extension TaskRecord {
    func availability(at now: Date) -> TaskAvailability {
        let reasons: [TaskUnavailabilityReason]
        if status == "pending", let date = waitUntil, date > now {
            reasons = [.waiting(until: date)]
        } else {
            reasons = []
        }
        return TaskAvailability(status: status, reasons: reasons)
    }
}
