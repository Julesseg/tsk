import Testing
@testable import TskNative

@Suite @MainActor struct EventKitReminderAccessPolicyTests {
    @Test func unpromptedUndeterminedAccessDoesNotRequestOrAuthorize() async throws {
        let access = EventKitReminderAccessPolicy()
        var requests = 0
        let allowed = try await access.requireAccess(authorization: { .notDetermined }, request: {
            requests += 1
            return true
        })
        #expect(!allowed)
        #expect(requests == 0)
    }

    @Test func currentFullAccessRequiresNoPermissionRequest() async throws {
        let access = EventKitReminderAccessPolicy()
        var requests = 0
        let allowed = try await access.requireAccess(authorization: { .fullAccess }, request: {
            requests += 1
            return false
        })
        #expect(allowed)
        #expect(requests == 0)
    }

    @Test func staleUndeterminedStatusRequiresANewGrantForEveryOperation() async throws {
        let access = EventKitReminderAccessPolicy()
        var requests = 0
        let request = {
            requests += 1
            return true
        }
        #expect(try await access.requestAccess(authorization: { .notDetermined }, request: request))
        #expect(requests == 1)
        for expected in 2...4 {
            #expect(try await access.requireAccess(authorization: { .notDetermined }, request: request))
            #expect(requests == expected)
        }
    }

    @Test func falseRevalidationBlocksAccessAndClearsRequestIntent() async throws {
        let access = EventKitReminderAccessPolicy()
        #expect(try await access.requestAccess(authorization: { .notDetermined }, request: { true }))
        #expect(try await !access.requireAccess(authorization: { .notDetermined }, request: { false }))
        var laterRequests = 0
        #expect(try await !access.requireAccess(authorization: { .notDetermined }, request: {
            laterRequests += 1
            return true
        }))
        #expect(laterRequests == 0)
    }

    @Test func requestErrorPropagatesWithoutAuthorizingAnotherOperation() async throws {
        enum RequestFailure: Error { case unavailable }
        let access = EventKitReminderAccessPolicy()
        #expect(try await access.requestAccess(authorization: { .notDetermined }, request: { true }))
        await #expect(throws: RequestFailure.self) {
            try await access.requireAccess(authorization: { .notDetermined }, request: { throw RequestFailure.unavailable })
        }
        var laterRequests = 0
        #expect(try await !access.requireAccess(authorization: { .notDetermined }, request: {
            laterRequests += 1
            return true
        }))
        #expect(laterRequests == 0)
    }

    @Test func knownRevocationNeverRequestsAndClearsEarlierIntent() async throws {
        for revoked in [EventKitAccessPublication.Authorization.denied, .restricted, .writeOnly, .unavailable] {
            let access = EventKitReminderAccessPolicy()
            #expect(try await access.requestAccess(authorization: { .notDetermined }, request: { true }))
            var requests = 0
            let request = {
                requests += 1
                return true
            }
            #expect(try await !access.requireAccess(authorization: { revoked }, request: request))
            #expect(try await !access.requireAccess(authorization: { .notDetermined }, request: request))
            #expect(try await !access.requestAccess(authorization: { revoked }, request: request))
            #expect(requests == 0)
        }
    }

    @Test func knownRevocationDuringNativeRequestRejectsItsTrueResult() async throws {
        for revoked in [EventKitAccessPublication.Authorization.denied, .restricted, .writeOnly, .unavailable] {
            let access = EventKitReminderAccessPolicy()
            var current = EventKitAccessPublication.Authorization.notDetermined
            #expect(try await access.requestAccess(authorization: { current }, request: { true }))
            let allowed = try await access.requireAccess(authorization: { current }, request: {
                current = revoked
                return true
            })
            #expect(!allowed)
            current = .notDetermined
            var laterRequests = 0
            #expect(try await !access.requireAccess(authorization: { current }, request: {
                laterRequests += 1
                return true
            }))
            #expect(laterRequests == 0)
        }
    }

    @Test func cancellationBeforeOrDuringRequestPreventsTheOperation() async throws {
        for cancelBefore in [true, false] {
            let access = EventKitReminderAccessPolicy()
            #expect(try await access.requestAccess(authorization: { .notDetermined }, request: { true }))
            var requests = 0, operations = 0
            let attempt = Task { @MainActor in
                if cancelBefore { withUnsafeCurrentTask { $0?.cancel() } }
                if try await access.requireAccess(authorization: { .notDetermined }, request: {
                    requests += 1
                    withUnsafeCurrentTask { $0?.cancel() }
                    return true
                }) { operations += 1 }
            }
            await #expect(throws: CancellationError.self) { try await attempt.value }
            #expect(requests == (cancelBefore ? 0 : 1))
            #expect(operations == 0)
        }
    }

    @Test func cancelledExplicitRequestNeverCallsNativePermissionAPI() async {
        let access = EventKitReminderAccessPolicy()
        var requests = 0
        let attempt = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await access.requestAccess(authorization: { .notDetermined }, request: {
                requests += 1
                return true
            })
        }
        await #expect(throws: CancellationError.self) { try await attempt.value }
        #expect(requests == 0)
    }

    @Test func cancellationDuringAuthorizationSamplingPreventsAnOperation() async {
        for current in [EventKitAccessPublication.Authorization.fullAccess, .notDetermined] {
            let access = EventKitReminderAccessPolicy()
            var requests = 0
            let attempt = Task { @MainActor in
                try await access.requireAccess(authorization: {
                    withUnsafeCurrentTask { $0?.cancel() }
                    return current
                }, request: {
                    requests += 1
                    return true
                })
            }
            await #expect(throws: CancellationError.self) { try await attempt.value }
            #expect(requests == 0)
        }
    }

    @Test func cancelledGrantCannotEnableLaterRevalidation() async throws {
        let access = EventKitReminderAccessPolicy()
        var samples = 0
        let attempt = Task { @MainActor in
            try await access.requestAccess(authorization: {
                samples += 1
                if samples == 2 { withUnsafeCurrentTask { $0?.cancel() } }
                return .notDetermined
            }, request: { true })
        }
        await #expect(throws: CancellationError.self) { try await attempt.value }
        var laterRequests = 0
        #expect(try await !access.requireAccess(authorization: { .notDetermined }, request: {
            laterRequests += 1
            return true
        }))
        #expect(laterRequests == 0)
    }

    @Test func falseInitialGrantNeverEnablesOperationRevalidation() async throws {
        let access = EventKitReminderAccessPolicy()
        #expect(try await !access.requestAccess(authorization: { .notDetermined }, request: { false }))
        var requests = 0
        #expect(try await !access.requireAccess(authorization: { .notDetermined }, request: {
            requests += 1
            return true
        }))
        #expect(requests == 0)
    }

    @Test func overlappingOperationsEachRequestFreshAccessAndUseTheirOwnResult() async throws {
        for firstGrant in [true, false] {
            let access = EventKitReminderAccessPolicy()
            #expect(try await access.requestAccess(authorization: { .notDetermined }, request: { true }))
            let pending = PendingPermissionRequest()
            let first = Task { @MainActor in
                try await access.requireAccess(authorization: { .notDetermined }, request: pending.request)
            }
            await pending.waitUntilRequested()
            var secondRequests = 0
            let secondAllowed = try await access.requireAccess(authorization: { .notDetermined }, request: {
                secondRequests += 1
                return true
            })
            pending.complete(firstGrant)
            #expect(try await first.value == firstGrant)
            #expect(secondAllowed)
            #expect(secondRequests == 1)
            var laterRequests = 0
            let laterAllowed = try await access.requireAccess(authorization: { .notDetermined }, request: {
                laterRequests += 1
                return true
            })
            #expect(laterAllowed == firstGrant)
            #expect(laterRequests == (firstGrant ? 1 : 0))
        }
    }

    @Test func initialRequestInFlightDoesNotAuthorizeOrPromptAnotherOperation() async throws {
        let access = EventKitReminderAccessPolicy()
        let pending = PendingPermissionRequest()
        let initial = Task { @MainActor in
            try await access.requestAccess(authorization: { .notDetermined }, request: pending.request)
        }
        await pending.waitUntilRequested()
        var requests = 0
        #expect(try await !access.requireAccess(authorization: { .notDetermined }, request: {
            requests += 1
            return true
        }))
        #expect(requests == 0)
        pending.complete(true)
        #expect(try await initial.value)
    }

    @Test func observedRevocationRejectsAConcurrentPendingGrant() async throws {
        let access = EventKitReminderAccessPolicy()
        var current = EventKitAccessPublication.Authorization.notDetermined
        #expect(try await access.requestAccess(authorization: { current }, request: { true }))
        let pending = PendingPermissionRequest()
        let first = Task { @MainActor in
            try await access.requireAccess(authorization: { current }, request: pending.request)
        }
        await pending.waitUntilRequested()
        current = .denied
        var requests = 0
        #expect(try await !access.requireAccess(authorization: { current }, request: {
            requests += 1
            return true
        }))
        pending.complete(true)
        #expect(try await !first.value)
        current = .notDetermined
        #expect(try await !access.requireAccess(authorization: { current }, request: {
            requests += 1
            return true
        }))
        #expect(requests == 0)
    }
}

@MainActor private final class PendingPermissionRequest {
    private var response: CheckedContinuation<Bool, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func request() async -> Bool {
        await withCheckedContinuation {
            response = $0
            started?.resume()
            started = nil
        }
    }

    func waitUntilRequested() async {
        if response != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func complete(_ granted: Bool) {
        response?.resume(returning: granted)
        response = nil
    }
}
