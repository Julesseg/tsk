#if canImport(CoreSpotlight)
import CTaskChampion
import Foundation
import TskCore

public struct TaskSpotlightIndexStatus: Codable, Equatable, Sendable {
    public let indexedCount: Int?
    public let lastSuccessfulIndex: Date?
    public let error: String?
}

@available(iOS 17.0, macOS 14.0, *)
public struct SpotlightTaskEffect: Sendable {
    public let directory: URL
    private let index: any TaskSpotlightIndex

    public init(directory: URL, index: (any TaskSpotlightIndex)? = nil) {
        self.directory = directory
        self.index = index ?? CoreSpotlightTaskIndex(namespace: Self.namespace(directory: directory))
    }

    public static func namespace(directory: URL) -> String {
        let parent = directory.deletingLastPathComponent()
        if parent.deletingLastPathComponent().lastPathComponent == "UITests" { return "com-julesseguin-tsk-tasks-test-" + parent.lastPathComponent }
        return "com-julesseguin-tsk-tasks-v1"
    }

    public func reconcile(manager: TaskManager) async -> TaskSpotlightIndexStatus {
        do {
            let lease = try await acquireAdmission()
            defer { lease.release() }
            do {
                let count = try await manager.reconcileSpotlight(using: index)
                let status = TaskSpotlightIndexStatus(indexedCount: count, lastSuccessfulIndex: Date(), error: nil)
                try save(status)
                return status
            } catch {
                let status = TaskSpotlightIndexStatus(indexedCount: nil, lastSuccessfulIndex: nil, error: error.localizedDescription)
                try? save(status)
                return status
            }
        } catch { return TaskSpotlightIndexStatus(indexedCount: nil, lastSuccessfulIndex: nil, error: error.localizedDescription) }
    }

    public static func status(directory: URL) throws -> TaskSpotlightIndexStatus {
        let file = directory.appendingPathComponent("spotlight-status.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return TaskSpotlightIndexStatus(indexedCount: nil, lastSuccessfulIndex: nil, error: nil) }
        return try JSONDecoder().decode(TaskSpotlightIndexStatus.self, from: Data(contentsOf: file))
    }

    private func save(_ status: TaskSpotlightIndexStatus) throws {
        let file = directory.appendingPathComponent("spotlight-status.json")
        let data = try JSONEncoder().encode(status)
        #if os(iOS)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: file, options: .atomic)
        #endif
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    private func acquireAdmission() async throws -> any TaskMutationLease {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent(".tsk-spotlight-index").path
        while true {
            try Task.checkCancellation()
            let descriptor = tsk_bridge_try_acquire_mutation(path)
            if descriptor >= 0 {
                let lease = NativeMutationLease(descriptor: descriptor)
                do { try Task.checkCancellation(); return lease }
                catch { lease.release(); throw error }
            }
            guard descriptor == -POSIXErrorCode.EWOULDBLOCK.rawValue || descriptor == -POSIXErrorCode.EINTR.rawValue else { throw TaskManagementError.storage(NSError(domain: NSPOSIXErrorDomain, code: Int(-descriptor)).localizedDescription) }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
#endif

#if canImport(CoreSpotlight)
@available(iOS 17.0, macOS 14.0, *)
extension SpotlightTaskEffect: TaskPostCommitEffect {
    public func apply(to manager: TaskManager, origin: TaskChangeOrigin) async { _ = await reconcile(manager: manager) }
}
#endif
