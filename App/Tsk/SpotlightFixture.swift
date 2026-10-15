#if DEBUG && targetEnvironment(simulator)
import Foundation
import TskCore
import TskNative

@MainActor func installStaleSpotlightFixture(store: TaskStore) async throws -> String {
    let environment = ProcessInfo.processInfo.environment
    guard environment["TSK_UI_ISOLATED_SIMULATOR"] == "1", let token = environment["TSK_TEST_SPOTLIGHT_FIXTURE"], let id = UUID(uuidString: token) else { throw CocoaError(.coderInvalidValue) }
    let namespace = SpotlightTaskEffect.namespace(directory: store.directory)
    try await SpotlightStaleResultFixture.install(manager: store.manager, directory: store.directory, token: id, index: CoreSpotlightTaskIndex(namespace: namespace))
    return "Actual stale fixture entry indexed for UUID " + id.uuidString
}

@MainActor func writeSpotlightReceivedFixture(store: TaskStore) async throws -> String {
    let environment = ProcessInfo.processInfo.environment
    guard environment["TSK_UI_ISOLATED_SIMULATOR"] == "1", let token = environment["TSK_TEST_SPOTLIGHT_FIXTURE"], UUID(uuidString: token) != nil,
          let server = environment["TSK_UI_SYNC_SERVER_URL"], let rawClient = environment["TSK_UI_SYNC_CLIENT_ID"], let client = UUID(uuidString: rawClient), let secret = environment["TSK_UI_SYNC_SECRET"] else { throw CocoaError(.coderInvalidValue) }
    let configuration = try SyncConfiguration(serverURL: server, clientID: client, encryptionSecret: secret)
    _ = try await store.manager.synchronize(using: configuration)
    let peer = TaskManager(replica: TaskChampionReplica(directory: store.directory.appendingPathComponent("spotlight-fixture-peer")))
    _ = try await peer.synchronize(using: configuration)
    guard let target = try await peer.tasks().first(where: { $0.description == "tsk remote " + token }) else { throw CocoaError(.fileNoSuchFile) }
    _ = try await peer.complete(id: target.id)
    _ = try await peer.synchronize(using: configuration)
    _ = try await store.manager.synchronize(using: configuration)
    await store.reload()
    return "Actual encrypted peer completion received for UUID " + target.id.uuidString
}
#endif
