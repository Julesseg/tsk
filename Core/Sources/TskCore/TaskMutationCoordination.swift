import Foundation

public protocol TaskMutationLease: Sendable {
    func release()
}

public protocol TaskMutationCoordinatingReplica: TaskReplica {
    func acquireMutationLease() async throws -> any TaskMutationLease
}

extension TaskManager {
    func beginMutation() async throws -> (any TaskMutationLease)? {
        if mutationInProgress {
            await withCheckedContinuation { mutationWaiters.append($0) }
        } else { mutationInProgress = true }
        do {
            try Task.checkCancellation()
            let lease = try await (replica as? any TaskMutationCoordinatingReplica)?.acquireMutationLease()
            do { try Task.checkCancellation() }
            catch { lease?.release(); throw error }
            return lease
        } catch { endMutation(nil); throw error }
    }

    func endMutation(_ lease: (any TaskMutationLease)?) {
        lease?.release()
        if mutationWaiters.isEmpty { mutationInProgress = false }
        else { mutationWaiters.removeFirst().resume() }
    }
}
