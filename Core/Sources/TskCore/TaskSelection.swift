import Foundation

public enum TaskSelectionMovement: Sendable {
    case next, previous
}

extension TaskManager {
    public nonisolated func selectedTasks(in tasks: [TaskRecord], from selection: Set<UUID>, startingAt initial: UUID, entering path: [UUID]) -> Set<UUID> {
        let eligible = Set(tasks.filter(\.canComplete).map(\.id))
        guard eligible.contains(initial) else { return selection }
        let selecting = !selection.contains(initial)
        var result = selection
        if selecting { result.insert(initial) }
        else { result.remove(initial) }
        for id in path where id != initial && eligible.contains(id) && selection.contains(id) != selecting {
            if !result.insert(id).inserted { result.remove(id) }
        }
        return result
    }

    public nonisolated func selectedTask(in tasks: [TaskRecord], from selection: UUID?, moving movement: TaskSelectionMovement) -> UUID? {
        var seen = Set<UUID>()
        let ids = tasks.map(\.id).filter { seen.insert($0).inserted }
        guard !ids.isEmpty else { return nil }
        guard let selection, let index = ids.firstIndex(of: selection) else {
            return movement == .next ? ids.first : ids.last
        }
        let offset = movement == .next ? 1 : -1
        return ids[min(max(index + offset, 0), ids.count - 1)]
    }
}
