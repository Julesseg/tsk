import Foundation
import Testing
import TskCore

@Test(arguments: [false, true])
func sweepReentryReversesChangedRowsWhileKeepingItsStartingTaskFixed(deselecting: Bool) async throws {
    let manager = TaskManager(replica: TestReplica())
    let first = try await manager.create(TaskDraft(description: "Starting task"))
    let second = try await manager.create(TaskDraft(description: "Crossed task"))
    let third = try await manager.create(TaskDraft(description: "Already in the intended state"))
    let fourth = try await manager.create(TaskDraft(description: "Last task"))
    let tasks = [first, second, third, fourth]
    let baseline: Set<UUID> = deselecting ? [first.id, second.id, fourth.id] : [third.id]
    func selection(entering path: [UUID]) -> Set<UUID> {
        manager.selectedTasks(in: tasks, from: baseline, startingAt: first.id, entering: path.map { TaskSelectionVisit(rowID: $0.uuidString, taskID: $0) })
    }
    let forward = selection(entering: [second.id, third.id, fourth.id])
    #expect(forward == (deselecting ? [] : Set(tasks.map(\.id))))
    let returned = selection(entering: [second.id, third.id, fourth.id, third.id, second.id, first.id])
    #expect(returned == (deselecting ? [second.id] : [first.id, third.id, fourth.id]))
    let repeated = selection(entering: [second.id, third.id, fourth.id, third.id, second.id, first.id, second.id])
    #expect(repeated == (deselecting ? [] : Set(tasks.map(\.id))))
}

@Test(arguments: [false, true])
func sweepDistinguishesUpcomingAppearancesFromReturningOverTheSameRow(deselecting: Bool) async throws {
    let manager = TaskManager(replica: TestReplica())
    let first = try await manager.create(TaskDraft(description: "Starting task"))
    let second = try await manager.create(TaskDraft(description: "Scheduled and due"))
    let baseline: Set<UUID> = deselecting ? [first.id, second.id] : []
    let scheduled = TaskSelectionVisit(rowID: "scheduled", taskID: second.id)
    let due = TaskSelectionVisit(rowID: "due", taskID: second.id)
    let duplicateStart = TaskSelectionVisit(rowID: "starting-task-due", taskID: first.id)
    let forward = manager.selectedTasks(in: [first, second], from: baseline, startingAt: first.id, entering: [scheduled, due, duplicateStart])
    #expect(forward == (deselecting ? [] : [first.id, second.id]))
    let returned = manager.selectedTasks(in: [first, second], from: baseline, startingAt: first.id, entering: [scheduled, due, duplicateStart, scheduled])
    #expect(returned == (deselecting ? [second.id] : [first.id]))
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
