import Foundation
import Testing
import TskCore
import TskNative

@Test func structuredFindReopensPersistedBytesStatusesDatesAndStablePagesWithoutChangingViews() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let replica = TaskChampionReplica(directory: directory)
    let a = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let b = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    _ = try await replica.create(id: a, attributes: ["description": "TRAIN one", "status": "pending", "project": "café", "tag_cafe\u{301}": "", "tag_rail": "", "priority": "H", "scheduled": "1000", "due": "2000", "wait": "500", "entry": "10"])
    _ = try await replica.create(id: b, attributes: ["description": "Train two", "status": "completed", "project": "café.Rail", "tag_rail": "", "entry": "10"])
    _ = try await replica.create(id: UUID(), attributes: ["description": "Train deleted", "status": "deleted", "entry": "11"])
    _ = try await replica.create(id: UUID(), attributes: ["description": "Train template", "status": "recurring", "entry": "12"])
    let manager = try await TaskChampionSession.open(directory: directory)
    let beforeViews = try await manager.savedViews()
    let all = try await manager.findTasks(FindTasksInput(status: .all))
    #expect(all.map(\.id) == [a, b])
    let input = FindTasksInput(description: "train", project: "café", tags: ["rail", "cafe\u{301}"], priority: "H", scheduled: TaskDateRange(from: Date(timeIntervalSince1970: 1000), through: Date(timeIntervalSince1970: 1000)), deadline: TaskDateRange(through: Date(timeIntervalSince1970: 2000)), waitingUntil: TaskDateRange(from: Date(timeIntervalSince1970: 500)))
    #expect(try await manager.findTasks(input).map(\.id) == [a])
    #expect(try await manager.findTasks(FindTasksInput(project: "cafe\u{301}")).isEmpty)
    #expect(try await manager.findTasks(FindTasksInput(tags: ["café"])).isEmpty)
    #expect(try await manager.findTasks(FindTasksInput(status: .all, limit: 1, offset: 1)).map(\.id) == [b])
    #expect(try await manager.findTasks(FindTasksInput(status: .completed)).map(\.id) == [b])
    #expect(try await manager.savedViews() == beforeViews)
}
