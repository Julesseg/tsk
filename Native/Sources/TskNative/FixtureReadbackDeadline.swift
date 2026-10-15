#if DEBUG
import Foundation

enum FixtureReadbackOutcome<Value: Sendable>: Sendable {
    case received(Value)
    case timedOut
}

@MainActor final class FixtureReadbackDeadline<Value: Sendable> {
    private var continuation: CheckedContinuation<FixtureReadbackOutcome<Value>, Never>?
    private var deadline: Task<Void, Never>?
    private var cancelFetch: (() -> Void)?

    static func observe(timeoutNanoseconds: UInt64, start: (@escaping @Sendable (Value) -> Void) -> (() -> Void)) async -> FixtureReadbackOutcome<Value> {
        let observation = FixtureReadbackDeadline()
        return await withCheckedContinuation { continuation in
            observation.continuation = continuation
            observation.deadline = Task { [weak observation] in
                do { try await Task.sleep(nanoseconds: timeoutNanoseconds) } catch { return }
                observation?.finish(.timedOut, cancel: true)
            }
            observation.cancelFetch = start { value in
                Task { @MainActor in observation.finish(.received(value), cancel: false) }
            }
        }
    }

    private func finish(_ outcome: FixtureReadbackOutcome<Value>, cancel: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        deadline?.cancel()
        deadline = nil
        let cancellation = cancelFetch
        cancelFetch = nil
        if cancel { cancellation?() }
        continuation.resume(returning: outcome)
    }
}
#endif
