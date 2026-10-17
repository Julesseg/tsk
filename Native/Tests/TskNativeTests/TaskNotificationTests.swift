import Foundation
import Testing
import TskCore
import TskNative

private actor NativeNotificationInspection: TaskPostCommitEffect {
    let directory: URL
    var savedIDs: [UUID] = []
    var warnings: [String] = []
    init(directory: URL) { self.directory = directory }
    func apply(to manager: TaskManager, origin: TaskChangeOrigin) async {
        do {
            let lease = try await TaskChampionReplica(directory: directory).acquireMutationLease()
            savedIDs = try await manager.tasks().map(\.id)
            lease.release()
            _ = try await manager.notificationState(using: LocalTaskNotificationStore(directory: directory))
        } catch { warnings.append(error.localizedDescription) }
    }
    func result() -> ([UUID], [String]) { (savedIDs, warnings) }
}

@Test func actualNativeMutationReleasesAdmissionBeforeAwaitedEffectsAndPreservesSavedIdentityOnIntegrationFailure() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let corrupt = Data("unreadable notification ledger".utf8)
    try corrupt.write(to: directory.appendingPathComponent("task-notifications.json"))
    let effect = NativeNotificationInspection(directory: directory)
    let manager = TaskChampionSession.makeManager(directory: directory, postCommitEffects: effect)
    let saved = try await manager.create(TaskDraft(description: "Durable despite integration failure", attributes: ["foreign_é": "one", "foreign_e\u{301}": "two"]))
    let outcome = await effect.result()
    #expect(outcome.0 == [saved.id])
    #expect(outcome.1.count == 1)
    #expect(try await TaskChampionSession.open(directory: directory).task(id: saved.id) == saved)
    #expect(try Data(contentsOf: directory.appendingPathComponent("task-notifications.json")) == corrupt)
    _ = try await manager.complete(id: saved.id)
    #expect(try await manager.task(id: saved.id).status == "completed")
}

@Test func nativeNotificationPreferencesPersistIndependentlyFromRawTaskDatesAndDoNotResetCorruption() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = TaskChampionSession.makeManager(directory: directory)
    let saved = try await manager.create(TaskDraft(description: "Keep dates", attributes: ["scheduled": "1792108800", "due": "1792141200"]))
    let store = LocalTaskNotificationStore(directory: directory)
    try await manager.saveNotificationPreferences(TaskNotificationPreferences(midnightReplacement: false, hour: 7, minute: 30), using: store)
    let reopened = TaskChampionSession.makeManager(directory: directory)
    let state = try await reopened.notificationState(using: LocalTaskNotificationStore(directory: directory))
    #expect(state.preferences == TaskNotificationPreferences(midnightReplacement: false, hour: 7, minute: 30))
    #expect(try await reopened.task(id: saved.id) == saved)
    try Data("corrupt".utf8).write(to: directory.appendingPathComponent("task-notifications.json"))
    await #expect(throws: (any Error).self) { try await reopened.saveNotificationPreferences(.init(), using: store) }
    #expect(try String(contentsOf: directory.appendingPathComponent("task-notifications.json"), encoding: .utf8) == "corrupt")
}
