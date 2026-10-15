import Foundation

public enum TaskChangeDomain: String, Codable, Sendable { case tasks, views, schema, synchronization }

public enum TaskChangeOrigin: String, Codable, Sendable { case local, synchronization, partialSynchronization }

public struct TaskChangeVersion: Equatable, Codable, Sendable {
    public var tasks: UUID
    public var views: UUID
    public var schema: UUID
    public var successfulSynchronization: UUID?
    public var taskOrigin: TaskChangeOrigin?

    public init(tasks: UUID, views: UUID, schema: UUID, taskOrigin: TaskChangeOrigin? = nil, successfulSynchronization: UUID? = nil) {
        self.tasks = tasks
        self.views = views
        self.schema = schema
        self.taskOrigin = taskOrigin
        self.successfulSynchronization = successfulSynchronization
    }

    public static let initial = TaskChangeVersion(tasks: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!, views: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!, schema: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)

    public mutating func advance(_ domain: TaskChangeDomain, origin: TaskChangeOrigin = .local) {
        switch domain {
        case .tasks: tasks = UUID(); taskOrigin = origin
        case .views: views = UUID()
        case .schema: schema = UUID()
        case .synchronization: successfulSynchronization = UUID()
        }
    }
}

public protocol TaskChangeTracking: Sendable {
    func current() async throws -> TaskChangeVersion
    func record(_ domain: TaskChangeDomain, origin: TaskChangeOrigin) async throws
}

public actor TaskChangeLedger: TaskChangeTracking {
    private var version = TaskChangeVersion.initial
    public init() {}
    public func current() -> TaskChangeVersion { version }
    public func record(_ domain: TaskChangeDomain, origin: TaskChangeOrigin) { version.advance(domain, origin: origin) }
}

extension TaskManager {
    public func changeVersion() async throws -> TaskChangeVersion {
        if let changePublicationError { throw TaskManagementError.storage("The change was saved, but participant refresh failed: \(changePublicationError)") }
        return try await changeTracking.current()
    }

    public func changeUpdates() -> AsyncThrowingStream<TaskChangeVersion, any Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let observer = Task { [weak self] in
                var prior: TaskChangeVersion?
                do {
                    while !Task.isCancelled, let self {
                        let version = try await self.changeVersion()
                        if version != prior { continuation.yield(version); prior = version }
                        try await Task.sleep(nanoseconds: 500_000_000)
                    }
                    continuation.finish()
                } catch is CancellationError { continuation.finish() }
                catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in observer.cancel() }
        }
    }

    func publishChange(_ domain: TaskChangeDomain, origin: TaskChangeOrigin = .local) async {
        do {
            try await changeTracking.record(domain, origin: origin)
            changePublicationError = nil
        } catch { changePublicationError = error.localizedDescription }
    }

    func publishReceivedChanges(since records: [TaskRecord]?, origin: TaskChangeOrigin) async {
        guard let current = try? await replica.tasks() else { return }
        let before = records.map { Dictionary(uniqueKeysWithValues: $0.map { ($0.id, $0) }) }
        if before != Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) }) { await publishChange(.tasks, origin: origin) }
    }
}
