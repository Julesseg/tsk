import CTaskChampion
import Foundation
import TskCore

public enum SharedStorageError: Error, LocalizedError, Sendable {
    case unavailable
    case initialization(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable: "Task storage is unavailable in this build. Your existing tasks have not been changed."
        case .initialization(let message): "Shared task storage could not be opened: \(message). Existing tasks were preserved."
        }
    }
}

public enum TaskChampionSession {
    public static let appGroupIdentifier = "group.com.julesseguin.tsk"

    public static func directory(testName: String? = nil) throws -> URL {
        try directory(testName: testName, allowMigration: Bundle.main.bundleURL.pathExtension != "appex")
    }

    public static func participantDirectory(testName: String? = nil) throws -> URL {
        try directory(testName: testName, allowMigration: false)
    }

    private static func directory(testName: String?, allowMigration: Bool) throws -> URL {
        #if os(iOS) || os(macOS)
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else { throw SharedStorageError.unavailable }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        if let testName {
            guard !testName.isEmpty, testName.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else { throw SharedStorageError.initialization("Invalid test replica name") }
            return try prepareShared(container: group.appendingPathComponent("UITests/\(testName)"), legacy: support.appendingPathComponent("UITests/\(testName)"), allowMigration: allowMigration)
        }
        return try prepareShared(container: group, legacy: support.appendingPathComponent("TaskChampion"), allowMigration: allowMigration)
        #else
        throw SharedStorageError.unavailable
        #endif
    }

    public static func prepareShared(container: URL, legacy: URL, library: String? = nil, allowMigration: Bool = true) throws -> URL {
        let destination = container.appendingPathComponent("TaskChampion", isDirectory: true)
        let legacyConnection = legacy.appendingPathComponent("sync-configuration.json")
        if allowMigration, !FileManager.default.fileExists(atPath: destination.path), FileManager.default.fileExists(atPath: legacyConnection.path) {
            _ = try JSONDecoder().decode(SyncConfiguration.self, from: Data(contentsOf: legacyConnection))
        }
        let request = try JSONEncoder().encode(MigrationRequest(path: destination.standardizedFileURL.path, source: legacy.standardizedFileURL.path, allowMigration: allowMigration))
        let library = library ?? ProcessInfo.processInfo.environment["TSK_TASKCHAMPION_LIBRARY"] ?? "libtsk_taskchampion.dylib"
        guard let input = String(data: request, encoding: .utf8), let output = tsk_bridge_request(library, input) else { throw SharedStorageError.initialization("The native storage library could not be loaded") }
        defer { tsk_bridge_free(output) }
        let result = try JSONDecoder().decode(MigrationResponse.self, from: Data(String(cString: output).utf8))
        if let error = result.error { throw SharedStorageError.initialization(error) }
        guard result.value == true else { throw SharedStorageError.initialization("Migration returned no confirmed result") }
        return destination
    }

    public static func makeManager(directory: URL, library: String? = nil, now: @escaping @Sendable () -> Date = { Date() }, calendar: Calendar = .autoupdatingCurrent) -> TaskManager {
        TaskManager(replica: TaskChampionReplica(directory: directory, library: library), now: now, calendar: calendar, viewDefinitions: LocalTaskViewStore(directory: directory), attributeDefinitions: LocalTaskAttributeStore(directory: directory))
    }

    public static func open(directory: URL, library: String? = nil) async throws -> TaskManager {
        let manager = makeManager(directory: directory, library: library)
        let configuration = try await SyncConfigurationStore(directory: directory, library: library).load()
        await manager.configureSynchronization(configuration)
        return manager
    }
}

private struct MigrationRequest: Encodable {
    let command = "prepareShared"
    let path: String
    let source: String
    let allowMigration: Bool
}

private struct MigrationResponse: Decodable {
    let value: Bool?
    let error: String?
}
