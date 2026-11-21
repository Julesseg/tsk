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

public struct TaskSelectionSweep: Sendable {
    public private(set) var selection: Set<UUID>
    private let selecting: Bool
    private let mutable: Set<UUID>
    private var visitedRows = Set<String>()
    private var previous: TaskSelectionVisit?

    public init?(in tasks: [TaskRecord], from selection: Set<UUID>, startingAt initial: UUID) {
        let eligible = Set(tasks.lazy.filter(\.canComplete).map(\.id))
        guard eligible.contains(initial) else { return nil }
        let selecting = !selection.contains(initial)
        self.selecting = selecting
        self.mutable = eligible.filter { $0 != initial && selection.contains($0) != selecting }
        self.selection = selection
        if selecting { self.selection.insert(initial) }
        else { self.selection.remove(initial) }
    }

    public mutating func enter(_ visit: TaskSelectionVisit) {
        let turningTask = previous.flatMap { $0.movement != visit.movement ? $0.taskID : nil }
        if let turningTask, mutable.contains(turningTask) { toggle(turningTask) }
        previous = visit
        let id = visit.taskID
        let firstVisit = visitedRows.insert(visit.rowID).inserted
        guard mutable.contains(id), id != turningTask else { return }
        if !firstVisit { toggle(id) }
        else if selecting { selection.insert(id) }
        else { selection.remove(id) }
    }

    private mutating func toggle(_ id: UUID) {
        if !selection.insert(id).inserted { selection.remove(id) }
    }
}

extension TaskManager {
    public nonisolated func selectedTasks(in tasks: [TaskRecord], from selection: Set<UUID>, startingAt initial: UUID, entering path: [TaskSelectionVisit]) -> Set<UUID> {
        guard var sweep = TaskSelectionSweep(in: tasks, from: selection, startingAt: initial) else { return selection }
        for visit in path { sweep.enter(visit) }
        return sweep.selection
    }
}
