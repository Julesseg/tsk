import Foundation

public protocol ReminderImportCoordinating: Sendable {
    func acquireImportLease() async throws -> any TaskMutationLease
    func importPaused() async throws -> Bool
    func setImportPaused(_ paused: Bool) async throws
}

public final class ReminderImportCoordinator: ReminderImportCoordinating, @unchecked Sendable {
    private let lock = NSLock()
    private var occupied = false
    private var paused = false
    public init() {}

    public func acquireImportLease() async throws -> any TaskMutationLease {
        while true {
            try Task.checkCancellation()
            if admit() { return ReminderImportLease(coordinator: self) }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
    public func importPaused() -> Bool { lock.withLock { paused } }
    public func setImportPaused(_ value: Bool) { lock.withLock { paused = value } }
    private func admit() -> Bool {
        lock.withLock {
            guard !occupied else { return false }
            occupied = true
            return true
        }
    }
    fileprivate func release() { lock.withLock { occupied = false } }
}

private final class ReminderImportLease: TaskMutationLease, @unchecked Sendable {
    private let lock = NSLock()
    private var coordinator: ReminderImportCoordinator?
    init(coordinator: ReminderImportCoordinator) { self.coordinator = coordinator }
    deinit { release() }
    func release() {
        lock.withLock { coordinator?.release(); coordinator = nil }
    }
}
