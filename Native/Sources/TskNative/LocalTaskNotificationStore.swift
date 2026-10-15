import CTaskChampion
import Foundation
import TskCore

public actor LocalTaskNotificationStore: TaskNotificationStateStore {
    private let directory: URL
    private var file: URL { directory.appendingPathComponent("task-notifications.json") }
    public init(directory: URL) { self.directory = directory }
    public func acquireLease() async throws -> any TaskMutationLease {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        while true {
            try Task.checkCancellation()
            let descriptor = tsk_bridge_try_acquire_mutation(directory.appendingPathComponent(".tsk-notifications").path)
            if descriptor >= 0 {
                let lease = NativeMutationLease(descriptor: descriptor)
                do { try Task.checkCancellation(); return lease }
                catch { lease.release(); throw error }
            }
            guard descriptor == -POSIXErrorCode.EWOULDBLOCK.rawValue || descriptor == -POSIXErrorCode.EINTR.rawValue else {
                throw TaskManagementError.storage(NSError(domain: NSPOSIXErrorDomain, code: Int(-descriptor)).localizedDescription)
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
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
