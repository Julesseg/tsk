import Foundation

public struct TaskViewSnapshot: Equatable, Sendable {
    public let tasks: [TaskRecord]
    public let allTasks: [TaskRecord]
    public let projects: [String]
}

public extension TaskManager {
    func viewSnapshot(query: TaskQuery = .all, project: TaskProjectSelection = .all) async throws -> TaskViewSnapshot {
        let records = try await tasks()
        let instant = now()
        let visible = records.filter { query.includes($0, now: instant, calendar: calendar) && project.includes($0) }
        return TaskViewSnapshot(tasks: visible, allTasks: records, projects: TaskProjectSelection.names(in: records))
    }

}
