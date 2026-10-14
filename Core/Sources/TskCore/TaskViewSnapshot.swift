import Foundation

public struct TaskViewSnapshot: Equatable, Sendable {
    public let tasks: [TaskRecord]
    public let allTasks: [TaskRecord]
    public let projects: [String]
}
