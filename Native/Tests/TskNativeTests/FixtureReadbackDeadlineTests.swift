#if DEBUG
import Foundation
import Testing
@testable import TskNative

@Test @MainActor func fixtureReadbackDeadlineCancelsBeforeCleanupAndIgnoresLateCallbacks() async {
    let fetch = ControlledFixtureFetch()
    let started = Date()
    let outcome = await FixtureReadbackDeadline<Int>.observe(timeoutNanoseconds: 10_000_000) { callback in
        fetch.callback = callback
        fetch.events.append("start")
        return {
            fetch.events.append("cancel")
            fetch.cancellations += 1
            callback(99)
        }
    }
    fetch.events.append("cleanup")
    guard case .timedOut = outcome else { Issue.record("A missing native callback must reach the diagnostic deadline"); return }
    #expect(Date().timeIntervalSince(started) < 1)
    #expect(fetch.events == ["start", "cancel", "cleanup"])
    #expect(fetch.cancellations == 1)
    fetch.callback?(1)
    fetch.callback?(2)
    await Task.yield()
    #expect(fetch.cancellations == 1)
}

@Test @MainActor func fixtureReadbackCallbackEnqueuedBeforeTokenReturnWinsOnce() async throws {
    let fetch = ControlledFixtureFetch()
    let outcome = await FixtureReadbackDeadline<Int>.observe(timeoutNanoseconds: 30_000_000) { callback in
        fetch.callback = callback
        callback(42)
        callback(43)
        return { fetch.cancellations += 1 }
    }
    guard case .received(let value) = outcome else { Issue.record("A synchronous native callback must retain its first result"); return }
    #expect(value == 42)
    fetch.callback?(44)
    try await Task.sleep(nanoseconds: 50_000_000)
    #expect(fetch.cancellations == 0)
}

@Test @MainActor func fixtureReadbackWithoutRetainedNativeCallbackStillReachesDeadline() async throws {
    let fetch = ControlledFixtureFetch()
    let observation = Task { @MainActor in
        let outcome = await FixtureReadbackDeadline<Int>.observe(timeoutNanoseconds: 10_000_000) { _ in
            return { fetch.cancellations += 1 }
        }
        if case .timedOut = outcome { fetch.timeoutObserved = true }
    }
    let limit = Date().addingTimeInterval(1)
    while !fetch.timeoutObserved, Date() < limit { try await Task.sleep(nanoseconds: 5_000_000) }
    #expect(fetch.timeoutObserved, "The deadline must own its lifetime even when native code discards the callback")
    #expect(fetch.cancellations == 1)
    if fetch.timeoutObserved { await observation.value }
    else { observation.cancel() }
}

@Test @MainActor func fixtureReadbackDistinguishesNilCallbackFromEmptyCollection() async {
    for reminders: [Int]? in [nil, []] {
        let outcome = await FixtureReadbackDeadline<(Int?, Bool)>.observe(timeoutNanoseconds: 30_000_000) { callback in
            callback((reminders?.count, reminders != nil))
            return {}
        }
        guard case .received(let result) = outcome else { Issue.record("Both nil and empty callbacks must finish before cleanup"); return }
        #expect(result.0 == reminders?.count)
        #expect(result.1 == (reminders != nil))
        if reminders == nil { #expect(result.0 == nil && !result.1) }
        else { #expect(result.0 == 0 && result.1) }
    }
}

@MainActor private final class ControlledFixtureFetch {
    var callback: (@Sendable (Int) -> Void)?
    var cancellations = 0
    var events: [String] = []
    var timeoutObserved = false
}
#endif
