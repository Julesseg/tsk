import CTaskChampion
import Foundation
import TskCore

public actor TaskChampionReplica: TaskSynchronizingReplica, TaskMutationCoordinatingReplica, TaskAtomicSnapshotMutatingReplica {
    private let directory: URL
    private let library: String

    public init(directory: URL, library: String? = nil) {
        self.directory = directory.resolvingSymlinksInPath().standardizedFileURL
        self.library = library ?? ProcessInfo.processInfo.environment["TSK_TASKCHAMPION_LIBRARY"] ?? "libtsk_taskchampion.dylib"
    }

    public func acquireMutationLease() async throws -> any TaskMutationLease {
        try await Task.detached { [directory] in try NativeMutationLease(directory: directory) }.value
    }

    public func tasks() async throws -> [TaskRecord] {
        try request(command: "tasks")
    }

    public func create(id: UUID, attributes: TaskAttributes) async throws -> TaskRecord {
        try request(command: "create", id: id, attributes: attributes)
    }

    public func update(id: UUID, changes: TaskAttributePatch) async throws -> TaskRecord {
        try request(command: "update", id: id, changes: changes)
    }

    public func updateAtomically(_ updates: [TaskAtomicUpdate]) async throws -> [TaskRecord] {
        try request(command: "updateAtomically", updates: updates)
    }

    public func updateAtomically(_ updates: [TaskAtomicUpdate], expecting records: [TaskRecord]) async throws -> [TaskRecord] {
        try request(command: "updateSnapshotAtomically", updates: updates, snapshot: records)
    }

    public func synchronize(using configuration: SyncConfiguration) async throws {
        do {
            let generation = tsk_bridge_sync_generation(library, directory.standardizedFileURL.path)
            try Task.checkCancellation()
            try await withTaskCancellationHandler {
                let operation = Task.detached { [self] in
                    let _: Bool = try request(command: "synchronize", configuration: configuration, syncGeneration: generation)
                }
                try await operation.value
            } onCancel: { [self] in
                _ = tsk_bridge_interrupt_sync(library, directory.standardizedFileURL.path)
            }
        } catch let error as SynchronizationError {
            throw error
        } catch {
            throw SynchronizationError.failed(error.localizedDescription)
        }
    }

    nonisolated private func request<T: Decodable>(command: String, id: UUID? = nil, attributes: TaskAttributes? = nil, changes: TaskAttributePatch? = nil, configuration: SyncConfiguration? = nil, syncGeneration: UInt64? = nil, updates: [TaskAtomicUpdate]? = nil, snapshot: [TaskRecord]? = nil) throws -> T {
        let request = Request(path: directory.standardizedFileURL.path, command: command, id: id, attributes: attributes, changes: changes, configuration: configuration, syncGeneration: syncGeneration, updates: updates, snapshot: snapshot)
        let data = try JSONEncoder().encode(request)
        guard let json = String(data: data, encoding: .utf8) else {
            throw TaskManagementError.storage("Could not encode the task operation.")
        }
        guard let output = tsk_bridge_request(library, json) else {
            throw TaskManagementError.storage("The TaskChampion native library could not be loaded. Build the pinned native bridge first.")
        }
        defer { tsk_bridge_free(output) }
        let response = try JSONDecoder().decode(Response<T>.self, from: Data(String(cString: output).utf8))
        if let error = response.error {
            if error == "TSK_SYNC_INTERRUPTED" { throw SynchronizationError.interrupted }
            if command == "synchronize" { throw SynchronizationError.failed(error) }
            throw TaskManagementError.storage(error)
        }
        guard let value = response.value else { throw TaskManagementError.storage("TaskChampion returned no result.") }
        return value
    }
}

private struct Request: Encodable {
    let path: String
    let command: String
    let id: UUID?
    let attributes: TaskAttributes?
    let changes: TaskAttributePatch?
    let configuration: SyncConfiguration?
    let syncGeneration: UInt64?
    let updates: [TaskAtomicUpdate]?
    let snapshot: [TaskRecord]?
}

private struct Response<T: Decodable>: Decodable {
    let value: T?
    let error: String?
}
