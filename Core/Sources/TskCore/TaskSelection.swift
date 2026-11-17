import Foundation

public enum TaskSelectionMovement: Equatable, Sendable {
    case next, previous
}

public struct TaskSelectionVisit: Sendable {
    public let rowID: String
    public let taskID: UUID
    public let movement: TaskSelectionMovement

    public init(rowID: String, taskID: UUID, moving movement: TaskSelectionMovement) {
        self.rowID = rowID
        self.taskID = taskID
        self.movement = movement
    }
}

extension TaskManager {
    public nonisolated func selectedTasks(in tasks: [TaskRecord], from selection: Set<UUID>, startingAt initial: UUID, entering path: [TaskSelectionVisit]) -> Set<UUID> {
        let eligible = Set(tasks.filter(\.canComplete).map(\.id))
        guard eligible.contains(initial) else { return selection }
        let selecting = !selection.contains(initial)
        let mutable = eligible.filter { $0 != initial && selection.contains($0) != selecting }
        var result = selection
        var visitedRows = Set<String>()
        var previous: TaskSelectionVisit?
        if selecting { result.insert(initial) }
        else { result.remove(initial) }
        for visit in path {
            let turningTask = previous.flatMap { $0.movement != visit.movement ? $0.taskID : nil }
            if let turningTask, mutable.contains(turningTask) {
                if !result.insert(turningTask).inserted { result.remove(turningTask) }
            }
            previous = visit
            let id = visit.taskID
            let firstVisit = visitedRows.insert(visit.rowID).inserted
            guard mutable.contains(id), id != turningTask else { continue }
            if firstVisit {
                if selecting { result.insert(id) }
                else { result.remove(id) }
            } else if !result.insert(id).inserted { result.remove(id) }
        }
        return result
    }
}
