import Foundation

public protocol TaskSynchronizingReplica: TaskReplica {
    func synchronize(using configuration: SyncConfiguration) async throws
}

public enum SynchronizationTrigger: Sendable {
    case appOpened, connectivityRestored, backgroundOpportunity, manualRetry
}

public enum SynchronizationState: Equatable, Sendable {
    case localOnly
    case ready
    case pending
    case syncing
    case synchronized(Date)
    case failed(String)
}

extension TaskManager {
    public func configureSynchronization(_ configuration: SyncConfiguration?) {
        guard synchronizationConfiguration != configuration else { return }
        synchronizationConfiguration = configuration
        synchronizationConfigurationGeneration += 1
        synchronizationRequested = false
        synchronizationTask?.cancel()
        finishSynchronizationWaiters(throwing: configuration == nil ? SynchronizationError.notConfigured : SynchronizationError.configurationChanged)
        setSynchronizationState(configuration == nil ? .localOnly : .ready)
    }

    public func synchronizationStatus() -> SynchronizationState { synchronizationState }

    public func synchronizationUpdates() -> AsyncStream<SynchronizationState> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<SynchronizationState>.makeStream(bufferingPolicy: .bufferingNewest(1))
        synchronizationObservers[id] = continuation
        continuation.yield(synchronizationState)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSynchronizationObserver(id) }
        }
        return stream
    }

    public func requestSynchronization(trigger: SynchronizationTrigger) {
        guard synchronizationConfiguration != nil else { return }
        synchronizationRequested = true
        if synchronizationTask == nil {
            setSynchronizationState(.pending)
            startSynchronization()
        }
    }

    public func suspendSynchronization() {
        synchronizationRequested = false
        synchronizationTask?.cancel()
        finishSynchronizationWaiters(throwing: CancellationError())
        setSynchronizationState(synchronizationConfiguration == nil ? .localOnly : .pending)
    }

    public func synchronize(using configuration: SyncConfiguration) async throws -> [TaskRecord] {
        configureSynchronization(configuration)
        return try await synchronize(trigger: .manualRetry)
    }

    public func synchronize(trigger: SynchronizationTrigger) async throws -> [TaskRecord] {
        guard synchronizationConfiguration != nil else { throw SynchronizationError.notConfigured }
        return try await withCheckedThrowingContinuation { continuation in
            synchronizationWaiters.append(continuation)
            requestSynchronization(trigger: trigger)
        }
    }

    func localChangeWasCommitted(tasks: [TaskRecord]) async {
        await publishChange(.tasks)
        if let scope = activeMutationScope { endMutation(scope) }
        await postCommitEffects.apply(to: self, origin: .local, locallyWritten: tasks)
        synchronizationLocalGeneration += 1
        guard synchronizationConfiguration != nil else { return }
        synchronizationRequested = true
        if synchronizationTask == nil {
            setSynchronizationState(.pending)
            startSynchronization()
        }
    }

    private func startSynchronization() {
        synchronizationTask = Task { await runSynchronization() }
    }

    private func runSynchronization() async {
        while synchronizationRequested, !Task.isCancelled,
              let configuration = synchronizationConfiguration {
            synchronizationRequested = false
            let configurationGeneration = synchronizationConfigurationGeneration
            let localGeneration = synchronizationLocalGeneration
            setSynchronizationState(.syncing)
            let recordsBeforeSync = try? await replica.tasks()
            do {
                guard let replica = replica as? any TaskSynchronizingReplica else {
                    throw SynchronizationError.unsupportedReplica
                }
                try await replica.synchronize(using: configuration)
                await publishReceivedChanges(since: recordsBeforeSync, origin: .synchronization)
                await publishChange(.synchronization, origin: .synchronization)
                await postCommitEffects.apply(to: self, origin: .synchronization)
                guard configurationGeneration == synchronizationConfigurationGeneration else { break }
                if Task.isCancelled { break }
                if localGeneration != synchronizationLocalGeneration || synchronizationRequested {
                    synchronizationRequested = true
                    setSynchronizationState(.pending)
                } else {
                    let records = try await tasks()
                    guard configurationGeneration == synchronizationConfigurationGeneration, !Task.isCancelled else { break }
                    if localGeneration != synchronizationLocalGeneration || synchronizationRequested {
                        synchronizationRequested = true
                        setSynchronizationState(.pending)
                    } else {
                        setSynchronizationState(.synchronized(now()))
                        let waiters = synchronizationWaiters
                        synchronizationWaiters.removeAll()
                        for waiter in waiters { waiter.resume(returning: records) }
                    }
                }
            } catch {
                await publishReceivedChanges(since: recordsBeforeSync, origin: .partialSynchronization)
                await postCommitEffects.apply(to: self, origin: .partialSynchronization)
                guard configurationGeneration == synchronizationConfigurationGeneration else { break }
                if Task.isCancelled { break }
                if error as? SynchronizationError == .interrupted {
                    synchronizationRequested = true
                    setSynchronizationState(.pending)
                    try? await Task.sleep(nanoseconds: 50_000_000)
                } else {
                    setSynchronizationState(.failed(error.localizedDescription))
                    finishSynchronizationWaiters(throwing: error)
                    break
                }
            }
        }
        synchronizationTask = nil
        if synchronizationRequested, synchronizationConfiguration != nil { startSynchronization() }
    }

    private func setSynchronizationState(_ state: SynchronizationState) {
        synchronizationState = state
        for observer in synchronizationObservers.values { observer.yield(state) }
    }

    private func finishSynchronizationWaiters(throwing error: any Error) {
        let waiters = synchronizationWaiters
        synchronizationWaiters.removeAll()
        for waiter in waiters { waiter.resume(throwing: error) }
    }

    private func removeSynchronizationObserver(_ id: UUID) { synchronizationObservers.removeValue(forKey: id) }
}
