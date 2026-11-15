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
    let created = try await AddTaskIntent(description: "Buy train tickets", project: "Travel", directory: directory).perform()
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
    await #expect(throws: TaskManagementError.emptyDescription) { try await AddTaskIntent(description: "  ", directory: directory).perform() }
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
    let result = try await AddTaskIntent(description: "Automatic native intent fixture", directory: directory).perform()
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

#if canImport(AppIntents)
@available(macOS 13, iOS 16, *)
@Test func rebuiltAddIntentPersistsEveryNamedInputAndReturnsDiscoverableTaskProperties() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let scheduled = Date(timeIntervalSince1970: 1793867400)
    let deadline = Date(timeIntervalSince1970: 1793953800)
    let waiting = Date(timeIntervalSince1970: 1793781000)
    let result = try await AddTaskIntent(description: "Book trip", project: "Travel", tags: ["trip", "rail"], priority: .high, scheduled: scheduled, deadline: deadline, waitingUntil: waiting, directory: directory).perform()
    let entity = try #require(result.value)
    let reopened = try await TaskChampionSession.open(directory: directory)
    let record = try await reopened.task(id: entity.id)
    #expect(record.project == "Travel")
    #expect(record.tags == ["rail", "trip"])
    #expect(record.priority == "H")
    #expect(record.plannedDate == scheduled && record.deadline == deadline && record.waitUntil == waiting)
    #expect(entity.uuid == entity.id.uuidString)
    #expect(entity.project == "Travel" && entity.tags == ["rail", "trip"])
    #expect(entity.priority == "H" && entity.scheduled == scheduled && entity.deadline == deadline && entity.waitingUntil == waiting)
    #expect(entity.status == "pending")
    #expect(entity.openTaskURL.absoluteString == "tsk://open-task?id=" + entity.id.uuidString)
    await #expect(throws: (any Error).self) { try await AddTaskIntent(description: "Invalid", tags: ["two words"], directory: directory).perform() }
    #expect(try await reopened.tasks().count == 1)
    let plain = try await AddTaskIntent(description: "No dates", directory: directory).perform()
    #expect(plain.value?.scheduled == nil && plain.value?.deadline == nil && plain.value?.waitingUntil == nil)
}
#endif

#if canImport(AppIntents)
@available(macOS 13, iOS 16, *)
@Test func structuredFindIntentReadsPersistentFiltersAndReturnsRichEntitiesForLaterActions() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let scheduled = Date(timeIntervalSince1970: 1793867400)
    let deadline = Date(timeIntervalSince1970: 1793953800)
    let waiting = Date(timeIntervalSince1970: 1793781000)
    let saved = try await AddTaskIntent(description: "Book TRAIN", project: "café", tags: ["rail", "cafe\u{301}"], priority: .high, scheduled: scheduled, deadline: deadline, waitingUntil: waiting, directory: directory).perform()
    let entity = try #require(saved.value)
    _ = try await AddTaskIntent(description: "Book train child", project: "café.Rail", tags: ["rail", "cafe\u{301}"], directory: directory).perform()
    _ = try await AddTaskIntent(description: "Book train other bytes", project: "cafe\u{301}", tags: ["rail", "café"], directory: directory).perform()
    let intent = FindTasksIntent(searchText: "train", project: "café", tags: ["rail", "cafe\u{301}"], priority: .high, scheduledFrom: scheduled, scheduledThrough: scheduled, deadlineFrom: deadline, deadlineThrough: deadline, waitingUntilFrom: waiting, waitingUntilThrough: waiting, directory: directory)
    let found = try await intent.perform()
    #expect(found.value?.map(\.id) == [entity.id])
    let task = try #require(found.value?.first)
    #expect(task.uuid == entity.id.uuidString && task.project?.utf8.elementsEqual("café".utf8) == true)
    #expect(task.tags.contains { $0.utf8.elementsEqual("cafe\u{301}".utf8) })
    #expect(task.priority == "H" && task.scheduled == scheduled && task.deadline == deadline && task.waitingUntil == waiting)
    #expect(task.status == "pending" && task.openTaskURL.absoluteString.hasSuffix(entity.id.uuidString))
    _ = try await CompleteTaskIntent(task: task, directory: directory).perform()
    #expect(try await intent.perform().value?.isEmpty == true)
    let completed = try await FindTasksIntent(project: "café", status: .completed, directory: directory).perform()
    #expect(completed.value?.map(\.id) == [entity.id])
    let page = try await FindTasksIntent(status: .all, sort: .description, limit: 1, offset: 1, directory: directory).perform()
    #expect(page.value?.first?.description == "Book train child")
    let empty = try await FindTasksIntent(offset: Int.max, directory: directory).perform()
    #expect(empty.value?.isEmpty == true)
    let wrongTag = try await FindTasksIntent(project: "café", tags: ["café"], status: .all, directory: directory).perform()
    #expect(wrongTag.value?.isEmpty == true)
    await #expect(throws: (any Error).self) { try await FindTasksIntent(limit: 0, directory: directory).perform() }
    await #expect(throws: (any Error).self) { try await FindTasksIntent(scheduledFrom: deadline, scheduledThrough: scheduled, directory: directory).perform() }
}
#endif
