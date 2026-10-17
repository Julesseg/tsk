import Foundation
import TskCore

enum NotificationSettingsReadError: Error, LocalizedError, Sendable {
    case timedOut
    var errorDescription: String? { "Notification settings are unavailable because the system did not respond. Saved tasks remain available." }
}

enum NotificationAuthorizationReader {
    static func read(timeoutNanoseconds: UInt64 = 2_000_000_000, request: @Sendable (@escaping @Sendable (TaskNotificationAuthorization) -> Void) -> Void) async throws -> TaskNotificationAuthorization {
        try Task.checkCancellation()
        let read = NotificationAuthorizationRead(timeoutNanoseconds: timeoutNanoseconds)
        let authorization = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard read.install(continuation) else { return }
                let timeout = Task {
                    do { try await Task.sleep(nanoseconds: timeoutNanoseconds) }
                    catch { return }
                    read.resolve(.failure(NotificationSettingsReadError.timedOut))
                }
                read.installTimeout(timeout)
                request { read.resolve(.success($0)) }
            }
        } onCancel: {
            read.resolve(.failure(CancellationError()))
        }
        try Task.checkCancellation()
        return authorization
    }
}

private final class NotificationAuthorizationRead: @unchecked Sendable {
    private let lock = NSLock()
    private let deadline: TimeInterval
    private var result: Result<TaskNotificationAuthorization, any Error>?
    private var continuation: CheckedContinuation<TaskNotificationAuthorization, any Error>?
    private var timeout: Task<Void, Never>?

    init(timeoutNanoseconds: UInt64) {
        deadline = ProcessInfo.processInfo.systemUptime + Double(timeoutNanoseconds) / 1_000_000_000
    }

    func install(_ continuation: CheckedContinuation<TaskNotificationAuthorization, any Error>) -> Bool {
        let completed: Result<TaskNotificationAuthorization, any Error>? = lock.withLock {
            if let result { return result }
            self.continuation = continuation
            return nil
        }
        if let completed {
            continuation.resume(with: completed)
            return false
        }
        return true
    }

    func installTimeout(_ timeout: Task<Void, Never>) {
        let completed = lock.withLock {
            guard result == nil else { return true }
            self.timeout = timeout
            return false
        }
        if completed { timeout.cancel() }
    }

    func resolve(_ result: Result<TaskNotificationAuthorization, any Error>) {
        let waiting = lock.withLock { () -> (CheckedContinuation<TaskNotificationAuthorization, any Error>?, Task<Void, Never>?, Result<TaskNotificationAuthorization, any Error>)? in
            guard self.result == nil else { return nil }
            let completed: Result<TaskNotificationAuthorization, any Error>
            if case .success = result, ProcessInfo.processInfo.systemUptime >= deadline {
                completed = .failure(NotificationSettingsReadError.timedOut)
            } else { completed = result }
            self.result = completed
            let waiting = (continuation, timeout, completed)
            continuation = nil
            timeout = nil
            return waiting
        }
        guard let (continuation, timeout, result) = waiting else { return }
        timeout?.cancel()
        continuation?.resume(with: result)
    }
}
