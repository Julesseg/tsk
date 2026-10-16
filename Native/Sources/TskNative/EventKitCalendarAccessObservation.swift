import Foundation

final class EventKitCalendarAccessObservation {
    private let policy = EventKitAccessPolicy()
    private var observedRefusal = false

    func effectiveAuthorization(
        isolation: isolated (any Actor)? = #isolation,
        authorization: () -> EventKitAccessPublication.Authorization,
        request: () async throws -> Bool
    ) async -> EventKitAccessPublication.Authorization {
        var nativeResult: Bool?
        let effective = await policy.effectiveAuthorization(isolation: isolation, authorization: authorization, request: {
            let granted = try await observeRequest(isolation: isolation, request: request)
            nativeResult = granted
            return granted
        })
        recordCompletedRequest(nativeResult)
        if effective == .fullAccess { observedRefusal = false }
        return effective == .notDetermined && observedRefusal ? .denied : effective
    }

    func requestAccess(
        isolation: isolated (any Actor)? = #isolation,
        authorization: () -> EventKitAccessPublication.Authorization,
        request: () async throws -> Bool
    ) async throws -> Bool {
        observedRefusal = false
        var nativeResult: Bool?
        let granted = try await policy.requestAccess(isolation: isolation, authorization: authorization, request: {
            let granted = try await observeRequest(isolation: isolation, request: request)
            nativeResult = granted
            return granted
        })
        recordCompletedRequest(nativeResult)
        return granted
    }

    func requireAccess(
        isolation: isolated (any Actor)? = #isolation,
        authorization: () -> EventKitAccessPublication.Authorization,
        request: () async throws -> Bool
    ) async throws -> Bool {
        var nativeResult: Bool?
        let granted = try await policy.requireAccess(isolation: isolation, authorization: authorization, request: {
            let granted = try await observeRequest(isolation: isolation, request: request)
            nativeResult = granted
            return granted
        })
        recordCompletedRequest(nativeResult)
        return granted
    }

    private func recordCompletedRequest(_ granted: Bool?) {
        guard let granted, !Task.isCancelled else { return }
        observedRefusal = !granted
    }

    private func observeRequest(
        isolation: isolated (any Actor)? = #isolation,
        request: () async throws -> Bool
    ) async throws -> Bool {
        observedRefusal = false
        let granted = try await request()
        try Task.checkCancellation()
        return granted
    }
}
