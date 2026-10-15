import Foundation
import Testing
@testable import TskCore

@Test func independentManagersSerializeSourceFetchThroughRemovalWithoutBlockingOrdinaryWrites() async throws {
    let replica = TestReplica(), settings = MoveConfigurationStore(device: UUID())
    let admission = ReminderImportCoordinator()
    let first = TaskManager(replica: replica, reminderImportConfiguration: settings, reminderImportAdmission: admission)
    let second = TaskManager(replica: replica, reminderImportConfiguration: settings, reminderImportAdmission: admission)
    try await first.configureContinuousReminders(enabled: true, mappings: [ReminderListMapping(listID: "work", project: "")])
    let source = AdmissionSource()
    let a = Task { try await first.runContinuousReminderImport(from: source) }
    try await source.waitForFetch()
    let b = Task { try await second.runContinuousReminderImport(from: source) }
    _ = try await second.create(TaskDraft(description: "Ordinary capture remains available"))
    #expect(try await second.tasks().map(\.description) == ["Ordinary capture remains available"])
    await source.releaseFetch()
    let results = try await [a.value, b.value]
    #expect(results.compactMap { $0 }.reduce(0) { $0 + $1.imported.count } == 1)
    #expect(try await first.tasks().count == 2)
    #expect(await source.present == false)
}

actor AdmissionSource: ReminderMoveSource {
    var present = true
    var fetched = false
    var continuation: CheckedContinuation<Void, Never>?
    func lists() -> [ReminderList] { [ReminderList(id: "work", title: "Work")] }
    func incompleteReminders(in listIDs: [String]) -> [ReminderSnapshot] { present ? [ReminderSnapshot(listID: "work", title: "Only one copy")] : [] }
    func moveCandidates(in listIDs: [String]) async -> [ReminderMoveCandidate] {
        let snapshot = incompleteReminders(in: listIDs)
        if !fetched { fetched = true; await withCheckedContinuation { continuation = $0 } }
        return snapshot.map { ReminderMoveCandidate(snapshot: $0, removeSource: { await self.remove() }) }
    }
    func waitForFetch() async throws {
        let deadline = Date().addingTimeInterval(10)
        while !fetched {
            guard Date() < deadline else { throw TaskManagementError.storage("Reminder source did not reach its fetch") }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
    func releaseFetch() { continuation?.resume(); continuation = nil }
    func remove() { present = false }
}

@Test func queuedScanRechecksDisabledSettingsAndCancellationReleasesAdmission() async throws {
    let replica = TestReplica(), settings = MoveConfigurationStore(device: UUID())
    let admission = ReminderImportCoordinator()
    let first = TaskManager(replica: replica, reminderImportConfiguration: settings, reminderImportAdmission: admission)
    let second = TaskManager(replica: replica, reminderImportConfiguration: settings, reminderImportAdmission: admission)
    try await first.configureContinuousReminders(enabled: true, mappings: [ReminderListMapping(listID: "work", project: "")])
    let source = AdmissionSource()
    let a = Task { try await first.runContinuousReminderImport(from: source) }
    try await source.waitForFetch()
    let canceled = Task { try await second.runContinuousReminderImport(from: source) }
    canceled.cancel()
    do { _ = try await canceled.value; Issue.record("Canceled queued scan must not fetch or save") }
    catch is CancellationError {} catch { Issue.record("Unexpected cancellation error: \(error)") }
    let queued = Task { try await second.runContinuousReminderImport(from: source) }
    try await second.configureContinuousReminders(enabled: false, mappings: [])
    await source.releaseFetch()
    let result = try #require(try await a.value)
    #expect(result.imported.isEmpty)
    #expect(result.stopped)
    #expect(try await queued.value == nil)
    #expect(try await first.tasks().isEmpty)
    #expect(await source.present)
    try await second.configureContinuousReminders(enabled: true, mappings: [ReminderListMapping(listID: "work", project: "")])
    #expect(try await second.runContinuousReminderImport(from: source)?.removedCount == 1)
}

@Test func failedDestinationPausesIndependentManagersBeforeTheyFetchAgain() async throws {
    let settings = MoveConfigurationStore(device: UUID()), admission = ReminderImportCoordinator()
    let failed = TaskManager(replica: AdmissionUnwritableReplica(), reminderImportConfiguration: settings, reminderImportAdmission: admission)
    let other = TaskManager(replica: TestReplica(), reminderImportConfiguration: settings, reminderImportAdmission: admission)
    try await failed.configureContinuousReminders(enabled: true, mappings: [ReminderListMapping(listID: "work", project: "")])
    let source = MoveTestSource(manager: failed)
    #expect(try await failed.runContinuousReminderImport(from: source)?.stopped == true)
    #expect(try await other.continuousReminderStatus().paused)
    #expect(try await other.runContinuousReminderImport(from: source) == nil)
    #expect(try await other.tasks().isEmpty)
    #expect(await source.remainingTitles() == ["First", "Second"])
}

private struct AdmissionUnwritableReplica: TaskReplica {
    func tasks() -> [TaskRecord] { [] }
    func create(id: UUID, attributes: TaskAttributes) throws -> TaskRecord { throw TaskManagementError.storage("No durable save") }
    func update(id: UUID, changes: TaskAttributePatch) throws -> TaskRecord { throw TaskManagementError.storage("No durable save") }
}
