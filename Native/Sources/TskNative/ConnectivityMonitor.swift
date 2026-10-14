#if canImport(Network)
import Foundation
@preconcurrency import Network

public final class ConnectivityMonitor: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "tsk.connectivity")
    private let lock = NSLock()
    private var wasAvailable: Bool?

    public init() {}

    public func restorations() -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            monitor.pathUpdateHandler = { [weak self] path in
                guard let self else { return }
                if didRestore(path.status == .satisfied) { continuation.yield(()) }
            }
            continuation.onTermination = { [weak self] _ in
                self?.monitor.cancel()
                self?.monitor.pathUpdateHandler = nil
            }
            monitor.start(queue: queue)
        }
    }

    private func didRestore(_ available: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let restored = wasAvailable == false && available
        wasAvailable = available
        return restored
    }
}
#endif
