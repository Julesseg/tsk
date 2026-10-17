import Foundation
import Testing
@testable import TskNative

@Suite @MainActor struct EventKitAccessPublicationTests {
    @Test func grantedAccessDoesNotReturnBeforeCurrentPublicAuthorizationConverges() async throws {
        var current = EventKitAccessPublication.Authorization.notDetermined
        var instant: UInt64 = 0
        var samples = 0, waits = 0
        let outcome = try await EventKitAccessPublication.waitForFullAccess(authorization: {
            samples += 1
            return current
        }, now: { instant }, sleep: { interval in
            #expect(current == .notDetermined)
            waits += 1
            instant += interval
            if waits == 2 { current = .fullAccess }
        })
        #expect(outcome == .ready)
        #expect(current == .fullAccess)
        #expect(samples == 3)
        #expect(waits == 2)
    }

    @Test func readyAndTerminalStatusesNeverWait() async throws {
        for status in [EventKitAccessPublication.Authorization.fullAccess, .denied, .restricted, .writeOnly, .unavailable] {
            var waits = 0
            let outcome = try await EventKitAccessPublication.waitForFullAccess(authorization: { status }, sleep: { _ in waits += 1 })
            #expect(outcome == (status == .fullAccess ? .ready : .insufficient))
            #expect(waits == 0)
        }
    }

    @Test func unresolvedPublicStatusStopsAtFiveSecondMonotonicDeadline() async throws {
        var instant: UInt64 = 1_000_000_000
        let outcome = try await EventKitAccessPublication.waitForFullAccess(authorization: { .notDetermined }, now: { instant }, sleep: { interval in instant += interval })
        #expect(outcome == .notReady)
        #expect(instant == 6_000_000_000)
    }

    @Test func readinessPublishedAfterDeadlineIsNotAcceptedAfterOversleptWait() async throws {
        var current = EventKitAccessPublication.Authorization.notDetermined
        var instant: UInt64 = 0
        var samples = 0
        let outcome = try await EventKitAccessPublication.waitForFullAccess(authorization: {
            samples += 1
            return current
        }, now: { instant }, sleep: { _ in
            instant = 6_000_000_000
            current = .fullAccess
        })
        #expect(outcome == .notReady)
        #expect(samples == 1)
    }

    @Test func everyCallSamplesCurrentAuthorizationWithoutCachingReadiness() async throws {
        var current = EventKitAccessPublication.Authorization.fullAccess
        #expect(try await EventKitAccessPublication.waitForFullAccess(authorization: { current }) == .ready)
        current = .denied
        #expect(try await EventKitAccessPublication.waitForFullAccess(authorization: { current }) == .insufficient)
    }

    @Test func cancellationWinsEvenWhenCurrentStatusIsReady() async throws {
        let operation = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await EventKitAccessPublication.waitForFullAccess(authorization: { .fullAccess })
        }
        await #expect(throws: CancellationError.self) { try await operation.value }
    }

    @Test func cancellationWhileWaitingPropagatesWithoutReturningAccess() async throws {
        let started = AccessPublicationSignal()
        let operation = Task { @MainActor in
            try await EventKitAccessPublication.waitForFullAccess(authorization: { .notDetermined }, sleep: { _ in
                started.signal()
                try await Task.sleep(nanoseconds: 60_000_000_000)
            })
        }
        await started.wait()
        operation.cancel()
        await #expect(throws: CancellationError.self) { try await operation.value }
    }

    @Test func cancellationDuringReadyStatusSamplingStillWinsBeforeSuccess() async {
        let operation = Task { @MainActor in
            try await EventKitAccessPublication.waitForFullAccess(authorization: {
                withUnsafeCurrentTask { $0?.cancel() }
                return .fullAccess
            })
        }
        await #expect(throws: CancellationError.self) { try await operation.value }
    }

    @Test func terminalStatusArrivingAfterPendingStopsWithoutFurtherWait() async throws {
        var current = EventKitAccessPublication.Authorization.notDetermined
        var waits = 0
        let outcome = try await EventKitAccessPublication.waitForFullAccess(authorization: { current }, sleep: { _ in
            waits += 1
            current = .denied
        })
        #expect(outcome == .insufficient)
        #expect(waits == 1)
    }

    @Test func sleepFailurePropagatesUnchanged() async {
        enum ControlledFailure: Error { case failed }
        await #expect(throws: ControlledFailure.self) {
            try await EventKitAccessPublication.waitForFullAccess(authorization: { .notDetermined }, sleep: { _ in throw ControlledFailure.failed })
        }
    }
}

@MainActor private final class AccessPublicationSignal {
    private var signaled = false
    private var continuation: CheckedContinuation<Void, Never>?
    func signal() { signaled = true; continuation?.resume(); continuation = nil }
    func wait() async {
        if signaled { return }
        await withCheckedContinuation { continuation = $0 }
    }
}
