import Foundation
import TskCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

final class NativeMutationLease: TaskMutationLease, @unchecked Sendable {
    private let mutex = NSLock()
    private var descriptor: Int32

    init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        descriptor = open(directory.appendingPathComponent(".tsk-semantic-mutation").path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw TaskManagementError.storage(String(cString: strerror(errno))) }
        while flock(descriptor, LOCK_EX) != 0 {
            if errno == EINTR { continue }
            let message = String(cString: strerror(errno))
            close(descriptor)
            descriptor = -1
            throw TaskManagementError.storage(message)
        }
    }

    deinit { release() }

    func release() {
        mutex.lock()
        defer { mutex.unlock() }
        guard descriptor >= 0 else { return }
        _ = flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }
}
