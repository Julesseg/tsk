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

private actor HeldSecondPublication: TaskChangeTracking {
    var version = TaskChangeVersion.initial
    var writes = 0
    var continuation: CheckedContinuation<Void, Never>?
    func current() -> TaskChangeVersion { version }
    func record(_ domain: TaskChangeDomain, origin: TaskChangeOrigin) async {
        writes += 1
        if writes == 2 { await withCheckedContinuation { continuation = $0 } }
        version.advance(domain, origin: origin)
    }
    func count() -> Int { writes }
    func resume() { continuation?.resume(); continuation = nil }
}

@Test func anEarlierPostCommitReturnCannotReleaseALaterMutationsOwnedScope() async throws {
    let effect = InspectingCommitEffect()
    let tracking = HeldSecondPublication()
    let manager = TaskManager(replica: TestReplica(), changeTracking: tracking, postCommitEffects: effect)
    let first = Task { try await manager.create(TaskDraft(description: "First")) }
    for _ in 0..<100 where await effect.count() == 0 { try await Task.sleep(nanoseconds: 1_000_000) }
    #expect(await effect.count() == 1)
    let second = Task { try await manager.create(TaskDraft(description: "Second")) }
    for _ in 0..<100 where await tracking.count() < 2 { try await Task.sleep(nanoseconds: 1_000_000) }
    #expect(await tracking.count() == 2)
    await effect.resume()
    _ = try await first.value
    let third = Task { try await manager.create(TaskDraft(description: "Third")) }
    try await Task.sleep(nanoseconds: 20_000_000)
    #expect(try await manager.tasks().count == 2)
    #expect(await tracking.count() == 2)
    await tracking.resume()
    _ = try await second.value
    _ = try await third.value
    #expect(try await manager.tasks().count == 3)
}
