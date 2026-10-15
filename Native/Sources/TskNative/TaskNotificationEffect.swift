#if canImport(UserNotifications)
import Foundation
import TskCore

public struct TaskNotificationEffect: TaskPostCommitEffect {
    private let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func apply(to manager: TaskManager, origin: TaskChangeOrigin) async { await apply(to: manager, origin: origin, locallyWritten: []) }
    public func apply(to manager: TaskManager, origin: TaskChangeOrigin, locallyWritten: [TaskRecord]) async {
        let trace = TaskParticipantDiagnostics.begin("postcommit.notifications")
        defer { TaskParticipantDiagnostics.end("postcommit.notifications", id: trace) }
        do {
            _ = try await Self.reconcile(manager: manager, directory: directory, locallyWritten: locallyWritten)
        } catch {
            let file = directory.appendingPathComponent("task-notifications-error.txt")
            try? Data(error.localizedDescription.utf8).write(to: file, options: .atomic)
        }
    }
    public static func reconcile(manager: TaskManager, directory: URL, locallyWritten: [TaskRecord] = []) async throws -> TaskNotificationReport {
        let report = try await manager.reconcileNotifications(center: UNTaskNotificationCenter(), store: LocalTaskNotificationStore(directory: directory), locallyWritten: locallyWritten)
        let file = directory.appendingPathComponent("task-notifications-error.txt")
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        return report
    }
    public static func warning(directory: URL) throws -> String? {
        do { return try String(contentsOf: directory.appendingPathComponent("task-notifications-error.txt"), encoding: .utf8) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
    }
}
#endif
