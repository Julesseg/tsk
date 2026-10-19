import Foundation
import Network
import os
import XCTest

final class DeferredSynchronizationServer: Sendable {
    private struct State: Sendable {
        var released = false
        var connections: [NWConnection] = []
    }

    private let listener: NWListener
    private let state = OSAllocatedUnfairLock(initialState: State())

    var port: UInt16? { listener.port?.rawValue }

    init(ready: XCTestExpectation) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        let queue = DispatchQueue(label: "tsk.deferred-sync-server")
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        let state = state
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            let released = state.withLock {
                if $0.released { return true }
                $0.connections.append(connection)
                return false
            }
            if released { Self.respond(connection) }
        }
        listener.start(queue: queue)
    }

    func finish() {
        let connections = state.withLock {
            $0.released = true
            let connections = $0.connections
            $0.connections.removeAll()
            return connections
        }
        connections.forEach(Self.respond)
    }

    func stop() {
        listener.cancel()
        finish()
    }

    private static func respond(_ connection: NWConnection) {
        let response = Data("HTTP/1.1 503 Service Unavailable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }
}
