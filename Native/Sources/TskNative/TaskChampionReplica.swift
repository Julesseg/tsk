import CTaskChampion
import Foundation
import TskCore

public actor TaskChampionReplica: TaskSynchronizingReplica {
    private let directory: URL
    private let library: String

    public init(directory: URL, library: String? = nil) {
        self.directory = directory
        self.library = library ?? ProcessInfo.processInfo.environment["TSK_TASKCHAMPION_LIBRARY"] ?? "libtsk_taskchampion.dylib"
    }

    public func tasks() async throws -> [TaskRecord] {
        try request(command: "tasks")
    }

    public func create(id: UUID, attributes: [String: String]) async throws -> TaskRecord {
        try request(command: "create", id: id, attributes: attributes)
    }

    public func synchronize(using configuration: SyncConfiguration) async throws {
        do {
            let _: Bool = try request(command: "synchronize", configuration: configuration)
        } catch let error as SynchronizationError {
            throw error
        } catch {
            throw SynchronizationError.failed(error.localizedDescription)
        }
    }

    private func request<T: Decodable>(command: String, id: UUID? = nil, attributes: [String: String]? = nil, configuration: SyncConfiguration? = nil) throws -> T {
        let request = Request(path: directory.path, command: command, id: id, attributes: attributes, configuration: configuration)
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
    let attributes: [String: String]?
    let configuration: SyncConfiguration?
}

private struct Response<T: Decodable>: Decodable {
    let value: T?
    let error: String?
}
