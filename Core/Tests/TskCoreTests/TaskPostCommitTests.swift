import Foundation
import Testing
import TskCore

private actor InspectingCommitEffect: TaskPostCommitEffect {
    var inspected = 0
    var releaseFirst: CheckedContinuation<Void, Never>?
    func apply(to manager: TaskManager, origin: TaskChangeOrigin) async {
        _ = try? await manager.notificationPlan()
        inspected += 1
        if inspected == 1 { await withCheckedContinuation { releaseFirst = $0 } }
    }
    func count() -> Int { inspected }
    func resume() { releaseFirst?.resume(); releaseFirst = nil }
}

@Test func durableMutationsAwaitEffectsOutsideTheirOwnedSemanticScope() async throws {
    let effect = InspectingCommitEffect()
    let manager = TaskManager(replica: TestReplica(), postCommitEffects: effect)
    let first = Task { try await manager.create(TaskDraft(description: "First")) }
    for _ in 0..<100 where await effect.count() == 0 { try await Task.sleep(nanoseconds: 1_000_000) }
    #expect(await effect.count() == 1)
    let second = try await manager.create(TaskDraft(description: "Second"))
    #expect(second.description == "Second")
    #expect(await effect.count() == 2)
    await effect.resume()
    _ = try await first.value
    _ = try await manager.complete(id: second.id)
    #expect(await effect.count() == 3)
}
