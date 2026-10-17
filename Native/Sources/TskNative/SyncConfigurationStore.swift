import CTaskChampion
import Foundation
import TskCore

public actor SyncConfigurationStore {
    private let directory: URL
    private let library: String

    public init(directory: URL, library: String? = nil) {
        self.directory = directory.resolvingSymlinksInPath().standardizedFileURL
        self.library = library ?? ProcessInfo.processInfo.environment["TSK_TASKCHAMPION_LIBRARY"] ?? "libtsk_taskchampion.dylib"
    }

    public func load() throws -> SyncConfiguration? {
        let response: ConfigurationResponse<SyncConfiguration> = try request(command: "configurationLoad")
        return response.value
    }

    public func save(_ configuration: SyncConfiguration) throws {
        let response: ConfigurationResponse<Bool> = try request(command: "configurationSave", configuration: configuration)
        guard response.value == true else { throw TaskManagementError.storage("Connection save was not confirmed") }
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: directory.appendingPathComponent("sync-configuration.json").path)
        #endif
    }

    public func remove() throws {
        let response: ConfigurationResponse<Bool> = try request(command: "configurationRemove")
        guard response.value == true else { throw TaskManagementError.storage("Connection removal was not confirmed") }
    }

    private func request<T: Decodable>(command: String, configuration: SyncConfiguration? = nil) throws -> ConfigurationResponse<T> {
        let data = try JSONEncoder().encode(ConfigurationRequest(path: directory.path, command: command, configuration: configuration))
        guard let input = String(data: data, encoding: .utf8), let output = tsk_bridge_request(library, input) else { throw TaskManagementError.storage("The native storage library could not be loaded") }
        defer { tsk_bridge_free(output) }
        let result = try JSONDecoder().decode(ConfigurationResponse<T>.self, from: Data(String(cString: output).utf8))
        if let error = result.error { throw TaskManagementError.storage(error) }
        return result
    }
}

private struct ConfigurationRequest: Encodable {
    let path: String
    let command: String
    let configuration: SyncConfiguration?
}

private struct ConfigurationResponse<T: Decodable>: Decodable {
    let value: T?
    let error: String?
}
