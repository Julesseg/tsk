import Foundation
import Testing
@testable import TskCore

@Test func continuousMoveCommitsTaskBeforeRemovingSourceAndStopsOnRemovalFailure() async throws {
    let manager = TaskManager(replica: TestReplica())
    let source = MoveTestSource(manager: manager, failRemoval: true)
    let result = try await manager.moveReminders(from: source, mappings: [ReminderListMapping(listID: "work", project: "Office")])
    #expect(result.imported.count == 1)
    #expect(result.removedCount == 0)
    #expect(result.failures.count == 1)
    #expect(result.failures[0].reason?.contains("Source removal failed") == true)
    #expect(await source.removalSawDurableTask)
    #expect(await source.remainingTitles() == ["First", "Second"])
    #expect(try await manager.tasks().map(\.description) == ["First"])
}

actor MoveTestSource: ReminderMoveSource {
    let manager: TaskManager
    let failRemoval: Bool
    var removalSawDurableTask = false
    var titles = ["First", "Second"]
    init(manager: TaskManager, failRemoval: Bool = false) { self.manager = manager; self.failRemoval = failRemoval }
    func lists() async throws -> [ReminderList] { [ReminderList(id: "work", title: "Work")] }
    func incompleteReminders(in listIDs: [String]) async throws -> [ReminderSnapshot] { titles.map { ReminderSnapshot(listID: "work", title: $0) } }
    func moveCandidates(in listIDs: [String]) async throws -> [ReminderMoveCandidate] {
        titles.map { title in ReminderMoveCandidate(snapshot: ReminderSnapshot(listID: "work", title: title), removeSource: { try await self.remove(title) }) }
    }
    func remainingTitles() -> [String] { titles }
    private func remove(_ title: String) async throws {
        removalSawDurableTask = try await manager.tasks().contains { $0.description == title }
        if failRemoval { throw TaskManagementError.storage("Source removal failed") }
        titles.removeAll { $0 == title }
    }
}

@Test func continuousConfigurationIsDisabledOnOtherDevicesAndPausesAutomaticRetriesAfterFailure() async throws {
    let device = UUID()
    let store = MoveConfigurationStore(device: device)
    let manager = TaskManager(replica: TestReplica(), reminderImportConfiguration: store)
    #expect(try await manager.continuousReminderStatus().active == false)
    try await manager.configureContinuousReminders(enabled: true, mappings: [ReminderListMapping(listID: "work", project: "Office")])
    #expect(try await manager.continuousReminderStatus().active)
    let source = MoveTestSource(manager: manager, failRemoval: true)
    #expect(try await manager.runContinuousReminderImport(from: source)?.imported.count == 1)
    #expect(try await manager.continuousReminderStatus().paused)
    #expect(try await manager.runContinuousReminderImport(from: source) == nil)
    #expect(try await manager.tasks().count == 1)
    let other = TaskManager(replica: TestReplica(), reminderImportConfiguration: MoveConfigurationStore(device: UUID(), configuration: try await store.load()))
    #expect(try await other.continuousReminderStatus().active == false)
    #expect(try await other.continuousReminderStatus().configuredOnAnotherDevice)
    #expect(try await other.runContinuousReminderImport(from: source) == nil)
    try await manager.configureContinuousReminders(enabled: false, mappings: [])
    #expect(try await manager.continuousReminderStatus().active == false)
}

actor MoveConfigurationStore: ContinuousReminderConfigurationStore {
    let device: UUID
    var configuration: ContinuousReminderConfiguration?
    init(device: UUID, configuration: ContinuousReminderConfiguration? = nil) { self.device = device; self.configuration = configuration }
    func currentDeviceID() -> UUID { device }
    func load() -> ContinuousReminderConfiguration? { configuration }
    func save(_ configuration: ContinuousReminderConfiguration) { self.configuration = configuration }
}

@Test func failedDestinationNeverRemovesSourceAndSuccessfulMovesLeaveNoPerItemMetadata() async throws {
    let failedManager = TaskManager(replica: MoveUnwritableReplica())
    let kept = MoveTestSource(manager: failedManager)
    let failure = try await failedManager.moveReminders(from: kept, mappings: [ReminderListMapping(listID: "work", project: "Office")])
    #expect(failure.imported.isEmpty)
    #expect(failure.failures.count == 1)
    #expect(await kept.remainingTitles() == ["First", "Second"])
    #expect(await kept.removalSawDurableTask == false)
    let manager = TaskManager(replica: TestReplica())
    let source = MoveTestSource(manager: manager)
    let result = try await manager.moveReminders(from: source, mappings: [ReminderListMapping(listID: "work", project: "Office")])
    #expect(result.imported.count == 2)
    #expect(result.removedCount == 2)
    #expect(await source.remainingTitles().isEmpty)
    #expect(result.imported.allSatisfy { $0.attributes.keys.sorted() == ["description", "entry", "modified", "project", "status"] })
}

private struct MoveUnwritableReplica: TaskReplica {
    func tasks() async throws -> [TaskRecord] { [] }
    func create(id: UUID, attributes: TaskAttributes) async throws -> TaskRecord { throw TaskManagementError.storage("Disk is full") }
    func update(id: UUID, changes: TaskAttributePatch) async throws -> TaskRecord { throw TaskManagementError.storage("Disk is full") }
}

@Test func sourceChangesCannotMakeTheSameReminderRetryWithinThePausedAutomaticAttempt() async throws {
    let settings = MoveConfigurationStore(device: UUID())
    let manager = TaskManager(replica: TestReplica(), reminderImportConfiguration: settings)
    try await manager.configureContinuousReminders(enabled: true, mappings: [ReminderListMapping(listID: "work", project: "")])
    let source = MoveTestSource(manager: manager, failRemoval: true)
    _ = try await manager.runContinuousReminderImport(from: source)
    for _ in 0..<4 { #expect(try await manager.runContinuousReminderImport(from: source) == nil) }
    #expect(try await manager.tasks().count == 1)
    _ = try await manager.runContinuousReminderImport(from: source, retry: true)
    #expect(try await manager.tasks().count == 2)
    #expect(await source.remainingTitles() == ["First", "Second"])
}

@Test func cancellationAfterDurableSaveNeverRemovesSourceAndReturnsInterruptedMove() async throws {
    let manager = TaskManager(replica: CancelAfterCreateReplica())
    let source = MoveTestSource(manager: manager)
    let attempt = Task { try await manager.moveReminders(from: source, mappings: [ReminderListMapping(listID: "work", project: "")]) }
    let result = try await attempt.value
    #expect(result.imported.count == 1)
    #expect(result.removedCount == 0)
    #expect(result.failures.count == 1)
    #expect(await source.remainingTitles() == ["First", "Second"])
    #expect(await source.removalSawDurableTask == false)
    #expect(try await manager.tasks().count == 1)
}

private actor CancelAfterCreateReplica: TaskReplica {
    var records: [TaskRecord] = []
    func tasks() -> [TaskRecord] { records }
    func create(id: UUID, attributes: TaskAttributes) -> TaskRecord {
        let record = TaskRecord(id: id, attributes: attributes); records.append(record)
        withUnsafeCurrentTask { $0?.cancel() }
        return record
    }
    func update(id: UUID, changes: TaskAttributePatch) throws -> TaskRecord { throw CocoaError(.userCancelled) }
}
