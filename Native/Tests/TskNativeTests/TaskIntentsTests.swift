#if canImport(AppIntents)
import AppIntents
import Foundation
import Testing
import TskCore
import TskNative

@available(macOS 13, iOS 16, *)
@Test func nativeIntentPerformCreatesFindsAndReopensTheAppDatasetWithStableIdentity() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let created = try await CreateTaskIntent(description: "Buy train tickets", project: "Travel", directory: directory).perform()
    let entity = try #require(created.value)
    let found = try await FindTasksIntent(searchText: "TRAIN", directory: directory).perform()
    #expect(found.value?.map(\.id) == [entity.id])
    let app = try await TaskChampionSession.open(directory: directory)
    let record = try await app.task(id: entity.id)
    #expect(record.description == "Buy train tickets")
    #expect(record.attributes["project"] == "Travel")
    _ = try await app.complete(id: entity.id)
    let unfinished = try await FindTasksIntent(directory: directory).perform()
    #expect(unfinished.value?.isEmpty == true)
    let completed = try await FindTasksIntent(status: .completed, directory: directory).perform()
    #expect(completed.value?.map(\.id) == [entity.id])
    await #expect(throws: TaskManagementError.emptyDescription) { try await CreateTaskIntent(description: "  ", directory: directory).perform() }
    #expect(try await app.tasks().count == 1)
}
#endif

#if canImport(AppIntents)
@available(macOS 13, iOS 16, *)
@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_SYNC_TEST_URL"] != nil))
func nativeIntentCaptureUsesPersistedConnectionAndAutomaticallyReachesAnIndependentReplica() async throws {
    let environment = ProcessInfo.processInfo.environment
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let directory = root.appendingPathComponent("intent")
    let client = try #require(environment["TSK_SYNC_TEST_CLIENT_ID"])
    let identity = try #require(UUID(uuidString: client))
    let configuration = try SyncConfiguration(serverURL: try #require(environment["TSK_SYNC_TEST_URL"]), clientID: identity, encryptionSecret: try #require(environment["TSK_SYNC_TEST_SECRET"]))
    try await SyncConfigurationStore(directory: directory).save(configuration)
    let result = try await CreateTaskIntent(description: "Automatic native intent fixture", directory: directory).perform()
    let taskID = try #require(result.value?.id)
    let peer = TaskManager(replica: TaskChampionReplica(directory: root.appendingPathComponent("peer")))
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while true {
        _ = try await peer.synchronize(using: configuration)
        if let received = try await peer.tasks().first(where: { $0.id == taskID }) {
            #expect(received.description == "Automatic native intent fixture")
            break
        }
        guard ContinuousClock.now < deadline else { throw TaskManagementError.storage("The persisted intent capture did not synchronize") }
        try await Task.sleep(for: .milliseconds(50))
    }
}
#endif
