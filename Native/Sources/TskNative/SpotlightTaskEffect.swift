#if canImport(CoreSpotlight)
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
        let trace = TaskParticipantDiagnostics.begin("spotlight.reconcile")
        defer { TaskParticipantDiagnostics.end("spotlight.reconcile", id: trace) }
        do {
            let admission = TaskParticipantDiagnostics.begin("spotlight.admission")
            let lease: any TaskMutationLease
            do {
                defer { TaskParticipantDiagnostics.end("spotlight.admission", id: admission) }
                lease = try await acquireAdmission()
            }
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
        return try await NativeMutationLease.acquire(path: directory.appendingPathComponent(".tsk-spotlight-index").path)
    }
}
#endif

#if canImport(CoreSpotlight)
@available(iOS 17.0, macOS 14.0, *)
extension SpotlightTaskEffect: TaskPostCommitEffect {
    public func apply(to manager: TaskManager, origin: TaskChangeOrigin) async { _ = await reconcile(manager: manager) }
}
#endif
