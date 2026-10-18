import Foundation

public protocol TaskMutationLease: Sendable {
    func release()
}

public protocol TaskMutationCoordinatingReplica: TaskReplica {
    func acquireMutationLease() async throws -> any TaskMutationLease
}

struct TaskMutationScope: Sendable {
    let id: UUID
    let lease: (any TaskMutationLease)?
}

extension TaskManager {
    func beginMutation() async throws -> TaskMutationScope {
        if mutationInProgress {
            await withCheckedContinuation { mutationWaiters.append($0) }
        } else { mutationInProgress = true }
        let id = UUID()
        activeMutationScope = TaskMutationScope(id: id, lease: nil)
        do {
            try Task.checkCancellation()
            let lease = try await (replica as? any TaskMutationCoordinatingReplica)?.acquireMutationLease()
            let scope = TaskMutationScope(id: id, lease: lease)
            activeMutationScope = scope
            do { try Task.checkCancellation() }
            catch { endMutation(scope); throw error }
            return scope
        } catch {
            if let scope = activeMutationScope, scope.id == id { endMutation(scope) }
            throw error
        }
    }

    func endMutation(_ scope: TaskMutationScope) {
        guard activeMutationScope?.id == scope.id else { return }
        activeMutationScope = nil
        scope.lease?.release()
        if mutationWaiters.isEmpty { mutationInProgress = false }
        else { mutationWaiters.removeFirst().resume() }
    }
}
