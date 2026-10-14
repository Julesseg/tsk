import Foundation
import TskCore

public enum TaskChampionSession {
    public static func directory(testName: String? = nil) -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent(testName.map { "UITests/\($0)" } ?? "TaskChampion", isDirectory: true)
    }

    public static func open(directory: URL, library: String? = nil) async throws -> TaskManager {
        let manager = TaskManager(replica: TaskChampionReplica(directory: directory, library: library))
        let configuration = try await SyncConfigurationStore(directory: directory).load()
        await manager.configureSynchronization(configuration)
        return manager
    }
}
