import Foundation

public struct TaskSynchronizationReceipt: Codable, Sendable {
    public let id: UUID
    public let tasks: [TaskRecord]
    public let completedAt: Date
    public init(id: UUID = UUID(), tasks: [TaskRecord], completedAt: Date) { self.id = id; self.tasks = tasks; self.completedAt = completedAt }
}

public struct TaskSynchronizationHistory: Codable, Sendable {
    public let baseline: [TaskRecord]
    public var success: TaskSynchronizationReceipt?
    public init(baseline: [TaskRecord], success: TaskSynchronizationReceipt? = nil) { self.baseline = baseline; self.success = success }
}

public protocol TaskSynchronizationReceiptStore: Sendable {
    func load() async throws -> TaskSynchronizationHistory?
}
