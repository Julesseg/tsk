#if DEBUG
import Foundation

final class TaskDiagnosticFileWriter: @unchecked Sendable {
    static let shared = TaskDiagnosticFileWriter()
    private let queue = DispatchQueue(label: "tsk.diagnostic-files", qos: .utility)
    private let lock = NSLock()
    private let delay: DispatchTimeInterval
    private var pending: [URL: @Sendable () throws -> Data] = [:]
    private var scheduled = false

    init(delay: DispatchTimeInterval = .milliseconds(100)) { self.delay = delay }

    func submit<Value: Encodable & Sendable>(_ value: Value, to file: URL) {
        enqueue({ try JSONEncoder().encode(value) }, to: file)
    }

    func submit(_ data: Data, to file: URL) {
        enqueue({ data }, to: file)
    }

    private func enqueue(_ encode: @escaping @Sendable () throws -> Data, to file: URL) {
        lock.lock()
        defer { lock.unlock() }
        pending[file] = encode
        guard !scheduled else { return }
        scheduled = true
        queue.asyncAfter(deadline: .now() + delay) { self.writePending() }
    }

    func flush() { queue.sync { writePending() } }

    func flushPending() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.writePending()
                continuation.resume()
            }
        }
    }

    private func writePending() {
        lock.lock()
        let batch = pending
        pending = [:]
        scheduled = false
        lock.unlock()
        for (file, encode) in batch {
            do { try encode().write(to: file, options: .atomic) }
            catch { NSLog("tsk owned diagnostic failed: %@", error.localizedDescription) }
        }
    }
}

enum TaskDiagnosticSettings {
    static func token(environment: [String: String]) -> String? {
        guard environment["TSK_UI_DIAGNOSTICS"] == "1",
              let token = environment["TSK_TEST_REPLICA_NAME"], UUID(uuidString: token) != nil else { return nil }
        return token
    }
}
#endif
