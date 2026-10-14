#if DEBUG
import Foundation
import TskCore
import TskNative

func installRecordedRecurrenceFixture() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let encoded = environment["TSK_TEST_RECORDED_RECURRENCE"] else { return }
    guard let name = environment["TSK_TEST_REPLICA_NAME"] else { throw CocoaError(.coderInvalidValue) }
    let directory = try TaskChampionSession.directory(testName: name)
    let replica = TaskChampionReplica(directory: directory)
    let records = try JSONDecoder().decode([TaskRecord].self, from: Data(encoded.utf8))
    let existing = try await replica.tasks()
    for record in records where !existing.contains(where: { $0.id == record.id }) {
        _ = try await replica.create(id: record.id, attributes: record.attributes)
    }
}
#endif
