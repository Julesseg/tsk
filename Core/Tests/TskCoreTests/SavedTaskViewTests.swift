import Testing
@testable import TskCore

@Test func missingOptionalSavedViewStorageIsAnExplicitReadFailure() async throws {
    let manager = TaskManager(replica: TestReplica())
    await #expect(throws: TaskViewError.storageNotConfigured) { try await manager.savedViews() }
    #expect(try await manager.tasks().isEmpty)
}
