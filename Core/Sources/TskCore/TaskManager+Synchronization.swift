import Foundation

public protocol TaskSynchronizingReplica: TaskReplica {
    func synchronize(using configuration: SyncConfiguration) async throws
}

extension TaskManager {
    public func synchronize(using configuration: SyncConfiguration) async throws -> [TaskRecord] {
        guard let replica = replica as? any TaskSynchronizingReplica else {
            throw SynchronizationError.unsupportedReplica
        }
        try await replica.synchronize(using: configuration)
        return try await tasks()
    }
}
