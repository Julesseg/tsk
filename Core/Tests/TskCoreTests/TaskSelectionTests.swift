import Foundation
import Testing
import TskCore

@Test(arguments: [false, true], [TaskSelectionMovement.next, .previous])
func sweepReentryReversesChangedRowsWhileKeepingItsStartingTaskFixed(deselecting: Bool, movement: TaskSelectionMovement) async throws {
    let manager = TaskManager(replica: TestReplica())
    let first = try await manager.create(TaskDraft(description: "Starting task"))
    let second = try await manager.create(TaskDraft(description: "Crossed task"))
    let third = try await manager.create(TaskDraft(description: "Already in the intended state"))
    let fourth = try await manager.create(TaskDraft(description: "Last task"))
    let tasks = [first, second, third, fourth]
    let baseline: Set<UUID> = deselecting ? [first.id, second.id, fourth.id] : [third.id]
    func visit(_ task: TaskRecord, moving movement: TaskSelectionMovement) -> TaskSelectionVisit {
        TaskSelectionVisit(rowID: task.id.uuidString, taskID: task.id, moving: movement)
    }
    let reverse: TaskSelectionMovement = movement == .next ? .previous : .next
    let path = [visit(second, moving: movement), visit(third, moving: movement), visit(fourth, moving: movement)]
    let returning = path + [visit(third, moving: reverse), visit(second, moving: reverse), visit(first, moving: reverse)]
    let forward = manager.selectedTasks(in: tasks, from: baseline, startingAt: first.id, entering: path)
    #expect(forward == (deselecting ? [] : Set(tasks.map(\.id))))
    let turned = manager.selectedTasks(in: tasks, from: baseline, startingAt: first.id, entering: path + [visit(third, moving: reverse)])
    #expect(turned == (deselecting ? [fourth.id] : [first.id, second.id, third.id]))
    let returned = manager.selectedTasks(in: tasks, from: baseline, startingAt: first.id, entering: returning)
    #expect(returned == (deselecting ? [second.id, fourth.id] : [first.id, third.id]))
    let repeated = manager.selectedTasks(in: tasks, from: baseline, startingAt: first.id, entering: returning + [visit(second, moving: movement)])
    #expect(repeated == (deselecting ? [fourth.id] : [first.id, second.id, third.id]))
}

@Test(arguments: [false, true])
func sweepDistinguishesUpcomingAppearancesFromReturningOverTheSameRow(deselecting: Bool) async throws {
    let manager = TaskManager(replica: TestReplica())
    let first = try await manager.create(TaskDraft(description: "Starting task"))
    let second = try await manager.create(TaskDraft(description: "Scheduled and due"))
    let baseline: Set<UUID> = deselecting ? [first.id, second.id] : []
    let scheduled = TaskSelectionVisit(rowID: "scheduled", taskID: second.id, moving: .next)
    let due = TaskSelectionVisit(rowID: "due", taskID: second.id, moving: .next)
    let duplicateStart = TaskSelectionVisit(rowID: "starting-task-due", taskID: first.id, moving: .next)
    let forward = manager.selectedTasks(in: [first, second], from: baseline, startingAt: first.id, entering: [scheduled, due, duplicateStart])
    #expect(forward == (deselecting ? [] : [first.id, second.id]))
    let returning = TaskSelectionVisit(rowID: "scheduled", taskID: second.id, moving: .previous)
    let returned = manager.selectedTasks(in: [first, second], from: baseline, startingAt: first.id, entering: [scheduled, due, duplicateStart, returning])
    #expect(returned == (deselecting ? [second.id] : [first.id]))
    let turned = manager.selectedTasks(in: [first, second], from: baseline, startingAt: first.id, entering: [scheduled, due, returning])
    #expect(turned == (deselecting ? [second.id] : [first.id]))
    let repeated = manager.selectedTasks(in: [first, second], from: baseline, startingAt: first.id, entering: [scheduled, due, returning, due])
    #expect(repeated == (deselecting ? [] : [first.id, second.id]))
}

@Test func keyboardSelectionCompletesOnlyTheChosenTaskAndKeepsItsAttributes() async throws {
    let manager = TaskManager(replica: TestReplica())
    let first = try await manager.create(TaskDraft(description: "First", attributes: ["opaque": "retain first"]))
    let second = try await manager.create(TaskDraft(description: "Second", attributes: ["opaque": "retain second"]))
    let rows = [first, second, first]
    #expect(manager.selectedTask(in: rows, from: nil, moving: .next) == first.id)
    let selection = try #require(manager.selectedTask(in: rows, from: first.id, moving: .next))
    #expect(selection == second.id)
    #expect(manager.selectedTask(in: rows, from: second.id, moving: .next) == second.id)
    #expect(manager.selectedTask(in: rows, from: second.id, moving: .previous) == first.id)
    let saved = try await manager.complete(id: selection)
    #expect(saved.id == second.id)
    #expect(saved.attributes["opaque"] == "retain second")
    #expect(try await manager.task(id: first.id).status == "pending")
    #expect(try await manager.tasks(query: .completed) == [saved])
}

@Test func keyboardNavigationUsesVisibleViewOrderAndRecoversAfterFiltering() async throws {
    let manager = TaskManager(replica: TestReplica())
    let hidden = try await manager.create(TaskDraft(description: "Hidden", attributes: ["project": "Other"]))
    let first = try await manager.create(TaskDraft(description: "One", attributes: ["project": "Work"]))
    let second = try await manager.create(TaskDraft(description: "Two", attributes: ["project": "Work"]))
    let visible = try await manager.viewSnapshot(query: .unfinished, project: .project("Work"))
    #expect(visible.tasks.count == 2)
    #expect(manager.selectedTask(in: visible.tasks, from: hidden.id, moving: .next) == visible.tasks.first?.id)
    #expect(manager.selectedTask(in: visible.tasks, from: nil, moving: .previous) == visible.tasks.last?.id)
    #expect(manager.selectedTask(in: [], from: first.id, moving: .next) == nil)
    _ = try await manager.complete(id: second.id)
    let remaining = try await manager.viewSnapshot(query: .unfinished, project: .project("Work"))
    #expect(manager.selectedTask(in: remaining.tasks, from: second.id, moving: .next) == first.id)
}
