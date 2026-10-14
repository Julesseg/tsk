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
