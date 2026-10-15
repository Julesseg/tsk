import Foundation
import Testing
import TskCore

@Test func aFinalSuccessfulReceiptAlertsOnlyNewMissedConstituentsOnceAcrossReopen() async throws {
    let replica = TestReplica()
    let history = MissedReceiptStore()
    let state = MissedStateStore()
    let center = MissedCenter()
    let manager = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 1000) }, notificationSynchronization: history)
    let known = try await manager.create(TaskDraft(description: "Already locally known", attributes: ["due": "100"]))
    _ = try await manager.reconcileNotifications(center: center, store: state)
    let learned = try await replica.create(id: UUID(), attributes: ["status": "pending", "description": "New missed", "due": "200", "foreign": "retain"])
    let completed = try await replica.create(id: UUID(), attributes: ["status": "completed", "description": "Same sync completed", "due": "300"])
    await history.set(TaskSynchronizationHistory(baseline: [known], success: TaskSynchronizationReceipt(tasks: [known, learned, completed], completedAt: Date(timeIntervalSince1970: 900))))
    let report = try await manager.reconcileNotifications(center: center, store: state)
    #expect((report.missed ?? []).map(\.taskID) == [learned.id])
    #expect(await center.immediate.map(\.taskID) == [learned.id])
    let reopened = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 1100) }, notificationSynchronization: history)
    _ = try await reopened.reconcileNotifications(center: center, store: state)
    #expect(await center.immediate.count == 1)
    #expect(try await reopened.task(id: learned.id).attributes["foreign"] == "retain")
}

actor MissedReceiptStore: TaskSynchronizationReceiptStore {
    var value: TaskSynchronizationHistory?
    func load() -> TaskSynchronizationHistory? { value }
    func set(_ value: TaskSynchronizationHistory) { self.value = value }
}
actor MissedStateStore: TaskNotificationStateStore {
    var value = TaskNotificationState()
    func acquireLease() -> any TaskMutationLease { MissedLease() }
    func load() -> TaskNotificationState { value }
    var rejectAccepted = false
    func rejectAcceptedSave(_ value: Bool) { rejectAccepted = value }
    func save(_ value: TaskNotificationState) throws {
        if rejectAccepted && !value.accepted.isEmpty { throw TaskManagementError.storage("Ledger unavailable after native acceptance") }
        self.value = value
    }
}
struct MissedLease: TaskMutationLease { func release() {} }
actor MissedCenter: TaskNotificationCenter {
    var immediate: [TaskNotificationRequest] = []
    var future: [TaskNotificationRequest] = []
    var failImmediate = false
    func reject(_ value: Bool) { failImmediate = value }
    var permission = TaskNotificationAuthorization.authorized
    var revokeOnImmediate = false
    func revokeAfterAdd() { revokeOnImmediate = true }
    func authorization() -> TaskNotificationAuthorization { permission }
    func requestAuthorization() -> TaskNotificationAuthorization { .authorized }
    var pendingHook: (@Sendable () async throws -> Void)?
    func onPending(_ hook: @escaping @Sendable () async throws -> Void) { pendingHook = hook }
    func pending() async throws -> [PendingTaskNotification] {
        try await pendingHook?()
        return future.map { PendingTaskNotification(identifier: $0.identifier, request: $0, nextTriggerDate: $0.fireDate) }
    }
    func add(_ request: TaskNotificationRequest) { future.removeAll { $0.identifier == request.identifier }; future.append(request) }
    func addImmediate(_ request: TaskNotificationRequest) throws {
        if failImmediate { throw TaskManagementError.storage("Native add rejected") }
        immediate.append(request)
        if revokeOnImmediate { permission = .denied }
    }
    func remove(identifiers: [String]) { future.removeAll { identifiers.contains($0.identifier) } }
}

@Test func localMutationContextSettlesOnlyTheWrittenTaskAndNotAnUnrelatedPartialArrival() async throws {
    let replica = TestReplica()
    let history = MissedReceiptStore()
    await history.set(TaskSynchronizationHistory(baseline: []))
    let state = MissedStateStore(), center = MissedCenter()
    let effect = MissedEffect(center: center, state: state)
    let manager = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 1000) }, postCommitEffects: effect, notificationSynchronization: history)
    let partial = try await replica.create(id: UUID(), attributes: ["status": "pending", "description": "Partial-only remote", "due": "200"])
    let local = try await manager.create(TaskDraft(description: "Local past date", attributes: ["due": "300"]))
    #expect(await center.immediate.isEmpty)
    await history.set(TaskSynchronizationHistory(baseline: [], success: TaskSynchronizationReceipt(tasks: [partial, local], completedAt: Date(timeIntervalSince1970: 900))))
    _ = try await manager.reconcileNotifications(center: center, store: state)
    #expect(await center.immediate.map(\.taskID) == [partial.id])
}

struct MissedEffect: TaskPostCommitEffect {
    let center: MissedCenter
    let state: MissedStateStore
    func apply(to manager: TaskManager, origin: TaskChangeOrigin) async {}
    func apply(to manager: TaskManager, origin: TaskChangeOrigin, locallyWritten: [TaskRecord]) async {
        _ = try? await manager.reconcileNotifications(center: center, store: state, locallyWritten: locallyWritten)
    }
}

@Test func acceptedImmediateWithFailedLedgerIsUncertainAcrossReopenAndNeverBlindlyReadded() async throws {
    let replica = TestReplica(), history = MissedReceiptStore(), state = MissedStateStore(), center = MissedCenter()
    let task = try await replica.create(id: UUID(), attributes: ["status": "pending", "description": "Crash window", "due": "200"])
    await history.set(TaskSynchronizationHistory(baseline: [], success: TaskSynchronizationReceipt(tasks: [task], completedAt: Date(timeIntervalSince1970: 900))))
    await state.rejectAcceptedSave(true)
    let manager = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 1000) }, notificationSynchronization: history)
    await #expect(throws: (any Error).self) { try await manager.reconcileNotifications(center: center, store: state) }
    await state.rejectAcceptedSave(false)
    let reopened = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 1100) }, notificationSynchronization: history)
    let report = try await reopened.reconcileNotifications(center: center, store: state)
    #expect(await center.immediate.count == 1)
    #expect(report.uncertainMissed?.map(\.taskID) == [task.id])
    #expect(report.retryableMissed?.isEmpty == true)
}

@Test func genuineNativeRejectionRetriesWithoutANewSuccessAndPartialOnlyEventsWaitForSuccess() async throws {
    let replica = TestReplica(), history = MissedReceiptStore(), state = MissedStateStore(), center = MissedCenter()
    let learned = try await replica.create(id: UUID(), attributes: ["status": "pending", "description": "Retry missed", "scheduled": "200", "due": "200"])
    await history.set(TaskSynchronizationHistory(baseline: [], success: TaskSynchronizationReceipt(tasks: [learned], completedAt: Date(timeIntervalSince1970: 900))))
    let manager = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 1000) }, notificationSynchronization: history)
    await center.reject(true)
    let failed = try await manager.reconcileNotifications(center: center, store: state)
    #expect(failed.retryableMissed?.count == 1)
    #expect(failed.uncertainMissed?.isEmpty == true)
    #expect(failed.errors.contains { $0.contains("Native add rejected") })
    let partial = try await replica.create(id: UUID(), attributes: ["status": "pending", "description": "Partial cannot settle", "due": "300"])
    await center.reject(false)
    let retried = try await manager.reconcileNotifications(center: center, store: state)
    #expect(retried.missed?.map(\.kind) == [.combined])
    #expect(await center.immediate.count == 1)
    await history.set(TaskSynchronizationHistory(baseline: [], success: TaskSynchronizationReceipt(tasks: [learned, partial], completedAt: Date(timeIntervalSince1970: 950))))
    _ = try await manager.reconcileNotifications(center: center, store: state)
    #expect(await center.immediate.map(\.taskID) == [learned.id, partial.id])
}

@Test func aDelayedSuccessfulReceiptCannotAlertNewerPartialOrCompletedDeletedOrRescheduledTasks() async throws {
    let replica = TestReplica(), history = MissedReceiptStore(), state = MissedStateStore(), center = MissedCenter()
    var success: [TaskRecord] = []
    for name in ["completed", "deleted", "rescheduled", "kept"] {
        success.append(try await replica.create(id: UUID(), attributes: ["status": "pending", "description": name, "due": "200"]))
    }
    await history.set(TaskSynchronizationHistory(baseline: [], success: TaskSynchronizationReceipt(tasks: success, completedAt: Date(timeIntervalSince1970: 900))))
    _ = try await replica.update(id: success[0].id, changes: ["status": "completed"])
    _ = try await replica.update(id: success[1].id, changes: ["status": "deleted"])
    _ = try await replica.update(id: success[2].id, changes: ["due": "3000"])
    let partial = try await replica.create(id: UUID(), attributes: ["status": "pending", "description": "new partial", "due": "300"])
    let manager = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 1000) }, notificationSynchronization: history)
    _ = try await manager.reconcileNotifications(center: center, store: state)
    #expect(await center.immediate.map(\.taskID) == [success[3].id])
    #expect(await center.future.map(\.taskID) == [success[2].id])
    let persisted = try await manager.notificationState(using: state)
    #expect(!persisted.known.contains { $0.taskID == partial.id })
}

@Test func missingDeliveredReadbackDoesNotReplayAcceptedConstituentsWhenPreferencesSplitTheGroup() async throws {
    let replica = TestReplica(), history = MissedReceiptStore(), state = MissedStateStore(), center = MissedCenter()
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let task = try await replica.create(id: UUID(), attributes: ["status": "pending", "description": "Combined by preference", "scheduled": "86400", "due": "118800", "foreign": "unchanged"])
    let receipt = TaskSynchronizationReceipt(tasks: [task], completedAt: Date(timeIntervalSince1970: 190000))
    await history.set(TaskSynchronizationHistory(baseline: [], success: receipt))
    let manager = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 200000) }, notificationSynchronization: history)
    let report = try await manager.reconcileNotifications(center: center, store: state, calendar: calendar)
    #expect(report.missed?.map(\.kind) == [.combined])
    try await manager.saveNotificationPreferences(TaskNotificationPreferences(midnightReplacement: false), using: state)
    await history.set(TaskSynchronizationHistory(baseline: [], success: TaskSynchronizationReceipt(tasks: [task], completedAt: Date(timeIntervalSince1970: 195000))))
    _ = try await manager.reconcileNotifications(center: center, store: state, calendar: calendar)
    #expect(await center.immediate.count == 1)
    #expect(try await manager.task(id: task.id) == task)
}

@Test func changingOneConstituentDuringReconciliationStillAlertsTheUnchangedSibling() async throws {
    let replica = TestReplica(), history = MissedReceiptStore(), state = MissedStateStore(), center = MissedCenter()
    let task = try await replica.create(id: UUID(), attributes: ["status": "pending", "description": "Combined race", "scheduled": "200", "due": "200"])
    await history.set(TaskSynchronizationHistory(baseline: [], success: TaskSynchronizationReceipt(tasks: [task], completedAt: Date(timeIntervalSince1970: 900))))
    await center.onPending {
        if !(await state.load().pendingMissed ?? []).isEmpty {
            _ = try await replica.update(id: task.id, changes: ["due": "3000", "description": "Latest title"])
        }
    }
    let manager = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 1000) }, notificationSynchronization: history)
    let report = try await manager.reconcileNotifications(center: center, store: state)
    #expect(report.missed?.count == 1)
    #expect(await center.immediate.first?.events == [TaskNotificationEvent(taskID: task.id, source: .planned, storedSeconds: 200)])
    #expect(await center.immediate.first?.kind == .planned)
    #expect(await center.immediate.first?.title == "Latest title")
}

@Test func everyRejectedMissedRequestRemainsRetryableWhenSeveralTasksArriveTogether() async throws {
    let replica = TestReplica(), history = MissedReceiptStore(), state = MissedStateStore(), center = MissedCenter()
    let first = try await replica.create(id: UUID(), attributes: ["status": "pending", "description": "First rejection", "due": "100"])
    let second = try await replica.create(id: UUID(), attributes: ["status": "pending", "description": "Second rejection", "due": "200"])
    await history.set(TaskSynchronizationHistory(baseline: [], success: TaskSynchronizationReceipt(tasks: [first, second], completedAt: Date(timeIntervalSince1970: 900))))
    let manager = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 1000) }, notificationSynchronization: history)
    await center.reject(true)
    let failed = try await manager.reconcileNotifications(center: center, store: state)
    #expect(Set(failed.retryableMissed?.map(\.taskID) ?? []) == Set([first.id, second.id]))
    await center.reject(false)
    _ = try await manager.reconcileNotifications(center: center, store: state)
    #expect(Set(await center.immediate.map(\.taskID)) == Set([first.id, second.id]))
}

@Test func uncertainImmediateCannotBeRegisteredAgainByMovingItsEffectiveTimeIntoTheFuture() async throws {
    let replica = TestReplica(), history = MissedReceiptStore(), state = MissedStateStore(), center = MissedCenter()
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let task = try await replica.create(id: UUID(), attributes: ["status": "pending", "description": "Midnight uncertainty", "due": "86400"])
    await history.set(TaskSynchronizationHistory(baseline: [], success: TaskSynchronizationReceipt(tasks: [task], completedAt: Date(timeIntervalSince1970: 86450))))
    let manager = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 86500) }, notificationSynchronization: history)
    try await manager.saveNotificationPreferences(TaskNotificationPreferences(midnightReplacement: false), using: state)
    await state.rejectAcceptedSave(true)
    await #expect(throws: (any Error).self) { try await manager.reconcileNotifications(center: center, store: state, calendar: calendar) }
    await state.rejectAcceptedSave(false)
    try await manager.saveNotificationPreferences(TaskNotificationPreferences(midnightReplacement: true), using: state)
    let report = try await manager.reconcileNotifications(center: center, store: state, calendar: calendar)
    #expect(await center.future.isEmpty)
    #expect(await center.immediate.count == 1)
    #expect(report.uncertainMissed?.count == 1)
}

@Test func seriesMutationsSettleTheirActualSavedChildrenWithoutSettlingUnchangedForeignRecords() async throws {
    let parent = UUID(), child = UUID(), foreign = UUID()
    let template = TaskRecord(id: parent, attributes: ["status": "recurring", "description": "Series", "recur": "weekly", "due": "200", "mask": "-"])
    let occurrence = TaskRecord(id: child, attributes: ["status": "pending", "description": "Child", "parent": parent.uuidString, "imask": "0", "due": "200"])
    let unrelated = TaskRecord(id: foreign, attributes: ["status": "pending", "description": "Unsettled foreign", "due": "50"])
    let replica = OccurrenceReplica(records: [template, occurrence, unrelated])
    let history = MissedReceiptStore(), state = MissedStateStore(), center = MissedCenter()
    await history.set(TaskSynchronizationHistory(baseline: []))
    let manager = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 100) }, postCommitEffects: MissedEffect(center: center, state: state), notificationSynchronization: history)
    let metadata = try await manager.previewSeriesMetadata(id: parent, changes: ["description": "Local series metadata"])
    _ = try await manager.applySeriesMetadata(metadata)
    var known = try await manager.notificationState(using: state).known
    #expect(known.contains(TaskNotificationEvent(taskID: child, source: .due, storedSeconds: 200)))
    #expect(!known.contains { $0.taskID == foreign })
    let transition = try await manager.previewSeriesTransition(id: parent, draft: TaskSeriesTransitionDraft(effectiveDate: Date(timeIntervalSince1970: 150), firstDue: Date(timeIntervalSince1970: 1000), recurrence: "weekly", generatorTimeZone: "UTC"))
    _ = try await manager.applySeriesTransition(transition)
    _ = try await manager.start(id: child)
    _ = try await manager.stop(id: child)
    known = try await manager.notificationState(using: state).known
    #expect(known.contains(TaskNotificationEvent(taskID: child, source: .due, storedSeconds: 1000)))
    #expect(!known.contains { $0.taskID == foreign })
    await history.set(TaskSynchronizationHistory(baseline: [], success: TaskSynchronizationReceipt(tasks: await replica.tasks(), completedAt: Date(timeIntervalSince1970: 1900))))
    let reopened = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 2000) }, notificationSynchronization: history)
    _ = try await reopened.reconcileNotifications(center: center, store: state)
    #expect(await center.immediate.map(\.taskID) == [foreign])
}

@Test func permissionRevokedDuringMissedSubmissionCancelsFutureRequestsAndReportsCurrentAuthorization() async throws {
    let replica = TestReplica(), history = MissedReceiptStore(), state = MissedStateStore(), center = MissedCenter()
    let missed = try await replica.create(id: UUID(), attributes: ["status": "pending", "description": "Permission race", "due": "200"])
    let future = try await replica.create(id: UUID(), attributes: ["status": "pending", "description": "Future must cancel", "due": "3000"])
    await history.set(TaskSynchronizationHistory(baseline: [], success: TaskSynchronizationReceipt(tasks: [missed, future], completedAt: Date(timeIntervalSince1970: 900))))
    await center.revokeAfterAdd()
    let manager = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 1000) }, notificationSynchronization: history)
    let report = try await manager.reconcileNotifications(center: center, store: state)
    #expect(report.authorization == .denied)
    #expect(report.registered.isEmpty)
    #expect(await center.future.isEmpty)
}
