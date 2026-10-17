import Foundation

enum SpotlightQueryReadError: Error, LocalizedError, Sendable {
    case timedOut
    var errorDescription: String? { "Spotlight search did not respond. Try searching again. Saved tasks remain available." }
}

struct SpotlightQueryOperation: Sendable {
    let start: @Sendable () -> Void
    let cancel: @Sendable () -> Void
}

enum SpotlightQueryReader {
    static func read<Item: Sendable>(timeoutNanoseconds: UInt64 = 45_000_000_000, request: @escaping @Sendable (@escaping @Sendable ([Item]) -> Void, @escaping @Sendable ((any Error)?) -> Void) -> SpotlightQueryOperation) async throws -> [Item] {
        try Task.checkCancellation()
        let read = SpotlightQueryRead<Item>(timeoutNanoseconds: timeoutNanoseconds)
        let items = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard read.install(continuation) else { return }
                let timeout = Task.detached {
                    do { try await Task.sleep(nanoseconds: read.remainingNanoseconds) }
                    catch { return }
                    read.finish(.timedOut)
                }
                read.installTimeout(timeout)
                Task.detached {
                    let operation = request({ read.append($0) }, { read.complete($0) })
                    read.start(operation)
                }
            }
        } onCancel: {
            read.finish(.cancelled)
        }
        try Task.checkCancellation()
        return items
    }
}

private final class SpotlightQueryRead<Item: Sendable>: @unchecked Sendable {
    enum Finish {
        case completed((any Error)?), timedOut, cancelled
    }

    private let lock = NSLock()
    private let deadline: TimeInterval
    private var items: [Item] = []
    private var result: Result<[Item], any Error>?
    private var continuation: CheckedContinuation<[Item], any Error>?
    private var timeout: Task<Void, Never>?
    private var operation: SpotlightQueryOperation?
    private var cancellationRequired = false
    private var nativeCompleted = false

    init(timeoutNanoseconds: UInt64) {
        deadline = ProcessInfo.processInfo.systemUptime + Double(timeoutNanoseconds) / 1_000_000_000
    }

    var remainingNanoseconds: UInt64 { UInt64(max(0, deadline - ProcessInfo.processInfo.systemUptime) * 1_000_000_000) }

    func install(_ continuation: CheckedContinuation<[Item], any Error>) -> Bool {
        let completed: Result<[Item], any Error>? = lock.withLock {
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

    func start(_ operation: SpotlightQueryOperation) {
        if ProcessInfo.processInfo.systemUptime >= deadline { finish(.timedOut) }
        let (shouldStart, shouldCancel) = lock.withLock {
            guard result == nil else { return (false, cancellationRequired && !nativeCompleted) }
            self.operation = operation
            return (true, false)
        }
        if shouldCancel { operation.cancel() }
        guard shouldStart, lock.withLock({ result == nil }) else { return }
        operation.start()
    }

    func append(_ items: [Item]) {
        lock.withLock {
            guard result == nil else { return }
            self.items += items
        }
    }

    func complete(_ error: (any Error)?) { finish(.completed(error)) }

    func finish(_ finish: Finish) {
        let waiting = lock.withLock { () -> (CheckedContinuation<[Item], any Error>?, Task<Void, Never>?, Result<[Item], any Error>, (@Sendable () -> Void)?)? in
            if case .completed = finish { nativeCompleted = true }
            guard result == nil else { return nil }
            let completed: Result<[Item], any Error>
            switch finish {
            case .completed(let error):
                if let error { completed = .failure(error) }
                else if ProcessInfo.processInfo.systemUptime >= deadline {
                    completed = .failure(SpotlightQueryReadError.timedOut)
                } else { completed = .success(items) }
            case .timedOut:
                completed = .failure(SpotlightQueryReadError.timedOut)
                cancellationRequired = true
            case .cancelled:
                completed = .failure(CancellationError())
                cancellationRequired = true
            }
            result = completed
            let cancel = cancellationRequired && !nativeCompleted ? operation?.cancel : nil
            operation = nil
            let waiting = (continuation, timeout, completed, cancel)
            continuation = nil
            timeout = nil
            items = []
            return waiting
        }
        guard let (continuation, timeout, result, cancel) = waiting else { return }
        timeout?.cancel()
        continuation?.resume(with: result)
        if let cancel { Task.detached { cancel() } }
    }
}
