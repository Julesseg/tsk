import Foundation
import Testing
import TskCore

@Test func taskListsExcludeActiveAndRetiredTemplatesWithoutChangingFilterResultsOrOccurrences() async throws {
    let replica = TestReplica()
    let template = try await replica.create(id: UUID(), attributes: ["description": "Daily review", "status": "recurring", "recur": "daily", "mask": "-", "project": "Home"])
    let retired = try await replica.create(id: UUID(), attributes: ["description": "Old review series", "status": "deleted", "recur": "weekly", "project": "Home"])
    let occurrence = try await replica.create(id: UUID(), attributes: ["description": "Today's review", "status": "pending", "parent": template.id.uuidString, "imask": "0", "project": "Home"])
    let completed = try await replica.create(id: UUID(), attributes: ["description": "Previous review", "status": "completed", "parent": retired.id.uuidString, "imask": "0", "project": "Home"])
    let ordinary = try await replica.create(id: UUID(), attributes: ["description": "Buy milk", "status": "pending", "project": "Home"])
    let manager = TaskManager(replica: replica)
    for snapshot in [try await manager.viewSnapshot(query: .all), try await manager.viewSnapshot(filter: "project:Home")] {
        #expect(Set(snapshot.listTasks.map(\.id)) == [occurrence.id, completed.id, ordinary.id])
        #expect(Set(snapshot.tasks.map(\.id)) == [template.id, retired.id, occurrence.id, completed.id, ordinary.id])
        #expect(snapshot.allTasks.contains(template))
        #expect(snapshot.allTasks.contains(retired))
    }
    #expect(try await manager.tasks(filter: "status:recurring") == [template])
    #expect(try await manager.recurringTemplates() == [template])
}
