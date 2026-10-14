import Foundation
import Testing
import TskCore

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
