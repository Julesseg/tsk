import Foundation
import TskCore

public actor LocalTaskNotificationStore: TaskNotificationStateStore {
    private let directory: URL
    private var file: URL { directory.appendingPathComponent("task-notifications.json") }
    public init(directory: URL) { self.directory = directory }
    public func acquireLease() async throws -> any TaskMutationLease {
        let trace = TaskParticipantDiagnostics.begin("notifications.admission")
        defer { TaskParticipantDiagnostics.end("notifications.admission", id: trace) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try await NativeMutationLease.acquire(path: directory.appendingPathComponent(".tsk-notifications").path)
    }
    public func load() throws -> TaskNotificationState {
        do { return try JSONDecoder().decode(TaskNotificationState.self, from: Data(contentsOf: file)) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return TaskNotificationState() }
    }
    public func save(_ state: TaskNotificationState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(state)
        #if os(iOS)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: file, options: .atomic)
        #endif
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
