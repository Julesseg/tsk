import Foundation

@MainActor final class EventKitReminderAccessPolicy {
    private var allowsLiveRevalidation = false

    func requestAccess(
        authorization: () -> EventKitAccessPublication.Authorization,
        request: () async throws -> Bool
    ) async throws -> Bool {
        do {
            try Task.checkCancellation()
            let current = authorization()
            try Task.checkCancellation()
            guard current == .notDetermined || current == .fullAccess else { allowsLiveRevalidation = false; return false }
            let granted = try await request()
            try Task.checkCancellation()
            let latest = authorization()
            try Task.checkCancellation()
            allowsLiveRevalidation = granted && (latest == .notDetermined || latest == .fullAccess)
            return allowsLiveRevalidation
        } catch {
            allowsLiveRevalidation = false
            throw error
        }
    }

    func requireAccess(
        authorization: () -> EventKitAccessPublication.Authorization,
        request: () async throws -> Bool
    ) async throws -> Bool {
        try Task.checkCancellation()
        let current = authorization()
        try Task.checkCancellation()
        if current == .fullAccess { return true }
        guard current == .notDetermined else { allowsLiveRevalidation = false; return false }
        guard allowsLiveRevalidation else { return false }
        return try await requestAccess(authorization: authorization, request: request)
    }
}
