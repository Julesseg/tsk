#if DEBUG && canImport(CoreSpotlight)
import Foundation
import TskCore

@available(iOS 17.0, macOS 14.0, *)
public enum SpotlightStaleResultFixture {
    public static func install(manager: TaskManager, directory: URL, token: UUID, index: any TaskSpotlightIndex) async throws {
        let lease = try await NativeMutationLease.acquire(path: directory.appendingPathComponent(".tsk-spotlight-index").path)
        defer { lease.release() }
        var items = TaskSpotlightItem.projected(from: try await manager.tasks(), namespace: index.namespace)
        items += TaskSpotlightItem.projected(from: [TaskRecord(id: token, attributes: ["status": "pending", "description": "tsk stale " + token.uuidString])], namespace: index.namespace)
        try await index.replace(items)
    }
}
#endif
