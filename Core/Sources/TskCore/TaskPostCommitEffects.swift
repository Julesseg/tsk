import Foundation

public protocol TaskPostCommitEffect: Sendable {
    func apply(to manager: TaskManager, origin: TaskChangeOrigin) async
    func apply(to manager: TaskManager, origin: TaskChangeOrigin, locallyWritten: [TaskRecord]) async
}

public extension TaskPostCommitEffect {
    func apply(to manager: TaskManager, origin: TaskChangeOrigin, locallyWritten: [TaskRecord]) async { await apply(to: manager, origin: origin) }
}

public struct TaskPostCommitEffects: TaskPostCommitEffect {
    private let effects: [any TaskPostCommitEffect]
    public init(_ effects: [any TaskPostCommitEffect] = []) { self.effects = effects }
    public func apply(to manager: TaskManager, origin: TaskChangeOrigin) async {
        for effect in effects { await effect.apply(to: manager, origin: origin) }
    }
    public func apply(to manager: TaskManager, origin: TaskChangeOrigin, locallyWritten: [TaskRecord]) async {
        for effect in effects { await effect.apply(to: manager, origin: origin, locallyWritten: locallyWritten) }
    }
}
