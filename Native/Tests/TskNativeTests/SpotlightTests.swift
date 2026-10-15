#if canImport(CoreSpotlight)
import Foundation
import Testing
import CoreSpotlight
import TskCore
import TskNative

@Test @available(macOS 14.0, *)
func actualOwnedSpotlightIndexQueriesStableUUIDAndRemovesCompletedTasks() async throws {
    let token = UUID().uuidString
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(token)
    defer { try? FileManager.default.removeItem(at: directory) }
    let namespace = "tsk.fixture." + token
    let index = CoreSpotlightTaskIndex(namespace: namespace, indexName: namespace)
    let manager = TaskChampionSession.makeManager(directory: directory)
    do {
        let task = try await manager.create(TaskDraft(description: "Owned synthetic Spotlight " + token, attributes: ["opaque": "keep"]))
        #expect(try await manager.reconcileSpotlight(using: index) == 1)
        let found = try await eventuallyIndexed(index, count: 1)
        #expect(found.first?.identifier == namespace + "/task/" + task.id.uuidString.lowercased())
        #expect(found.first?.title == task.description)
        _ = try await manager.update(id: task.id, changes: ["description": "Changed synthetic " + token])
        _ = try await manager.reconcileSpotlight(using: index)
        let updated = try await eventuallyIndexed(index, count: 1, title: "Changed synthetic " + token)
        #expect(updated.first?.identifier == found.first?.identifier)
        _ = try await manager.complete(id: task.id)
        _ = try await manager.reconcileSpotlight(using: index)
        #expect(try await eventuallyIndexed(index, count: 0).isEmpty)
        #expect(try await manager.task(id: task.id).attributes["opaque"] == "keep")
        try await index.replace([])
    } catch { try? await index.replace([]); throw error }
}

@available(macOS 14.0, *)
private func eventuallyIndexed(_ index: CoreSpotlightTaskIndex, count: Int, title: String? = nil) async throws -> [SpotlightIndexedItem] {
    for _ in 0..<40 {
        let values = try await index.query()
        if values.count == count, title == nil || values.first?.title == title { return values }
        try await Task.sleep(for: .milliseconds(250))
    }
    let values = try await index.query()
    Issue.record("Actual Spotlight index did not converge to expected count/title; observed \(values)")
    return values
}
#endif
