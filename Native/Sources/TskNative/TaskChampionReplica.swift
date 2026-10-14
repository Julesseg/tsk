import CTaskChampion
import Foundation
import TskCore

public actor TaskChampionReplica: TaskReplica {
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

    public func update(id: UUID, changes: [String: String?]) async throws -> TaskRecord {
        try request(command: "update", id: id, changes: changes)
    }

    private func request<T: Decodable>(command: String, id: UUID? = nil, attributes: [String: String]? = nil, changes: [String: String?]? = nil) throws -> T {
        let request = Request(path: directory.path, command: command, id: id, attributes: attributes, changes: changes)
        let data = try JSONEncoder().encode(request)
        guard let json = String(data: data, encoding: .utf8) else {
            throw TaskManagementError.storage("Could not encode the task operation.")
        }
        guard let output = tsk_bridge_request(library, json) else {
            throw TaskManagementError.storage("The TaskChampion native library could not be loaded. Build the pinned native bridge first.")
        }
        defer { tsk_bridge_free(output) }
        let response = try JSONDecoder().decode(Response<T>.self, from: Data(String(cString: output).utf8))
        if let error = response.error { throw TaskManagementError.storage(error) }
        guard let value = response.value else { throw TaskManagementError.storage("TaskChampion returned no result.") }
        return value
    }
}

private struct Request: Encodable {
    let path: String
    let command: String
    let id: UUID?
    let attributes: [String: String]?
    let changes: [String: String?]?
}

private struct Response<T: Decodable>: Decodable {
    let value: T?
    let error: String?
}
