import CTaskChampion
import Foundation
import TskCore

final class NativeMutationLease: TaskMutationLease, @unchecked Sendable {
    private let mutex = NSLock()
    private var descriptor: Int32

    static func acquire(path: String) async throws -> NativeMutationLease {
        while true {
            try Task.checkCancellation()
            let descriptor = tsk_bridge_try_acquire_mutation(path)
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

    init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        descriptor = tsk_bridge_acquire_mutation(directory.appendingPathComponent(".tsk-semantic-mutation").path)
        guard descriptor >= 0 else { throw TaskManagementError.storage(NSError(domain: NSPOSIXErrorDomain, code: Int(-descriptor)).localizedDescription) }
    }

    init(descriptor: Int32) { self.descriptor = descriptor }

    deinit { release() }

    func release() {
        mutex.lock()
        defer { mutex.unlock() }
        guard descriptor >= 0 else { return }
        tsk_bridge_release_mutation(descriptor)
        descriptor = -1
    }
}
