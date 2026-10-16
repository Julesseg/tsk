import Foundation
import Testing
import TskCore
@testable import TskNative

@Test func notificationSettingsReadTimesOutWithoutACallback() async throws {
    let native = ControlledNotificationSettings()
    let read = Task { try await NotificationAuthorizationReader.read(timeoutNanoseconds: 1_000_000, request: native.request) }
    await native.waitForRequest()
    let cleanup = native.scheduleCleanupReply()
    defer { cleanup.cancel() }
    await #expect(throws: NotificationSettingsReadError.self) { try await read.value }
    native.reply(.authorized)
    native.reply(.denied)
    cleanup.cancel()
    await cleanup.value
}

@Test func notificationSettingsReadPreservesEveryTimelyAuthorizationAndIgnoresDuplicateReplies() async throws {
    for expected in [TaskNotificationAuthorization.notDetermined, .denied, .authorized, .provisional, .ephemeral, .unavailable] {
        let actual = try await NotificationAuthorizationReader.read { completion in
            completion(expected)
            completion(.unavailable)
        }
        #expect(actual == expected)
    }
}

@Test func notificationSettingsReadCancellationReleasesWaitAndRejectsLateReply() async throws {
    let native = ControlledNotificationSettings()
    let read = Task { try await NotificationAuthorizationReader.read(timeoutNanoseconds: 60_000_000_000, request: native.request) }
    await native.waitForRequest()
    let cleanup = native.scheduleCleanupReply()
    defer { cleanup.cancel() }
    read.cancel()
    await #expect(throws: CancellationError.self) { try await read.value }
    native.reply(.authorized)
    native.reply(.denied)
    cleanup.cancel()
    await cleanup.value
}

@Test func notificationSettingsReadDoesNotStartForAnAlreadyCancelledCaller() async throws {
    let native = ControlledNotificationSettings()
    let read = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await NotificationAuthorizationReader.read(request: native.request)
    }
    await #expect(throws: CancellationError.self) { try await read.value }
    #expect(!native.requested)
}

private final class ControlledNotificationSettings: @unchecked Sendable {
    private let lock = NSLock()
    private var completion: (@Sendable (TaskNotificationAuthorization) -> Void)?
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private let recoversAfterFirstRequest: Bool
    init(recoversAfterFirstRequest: Bool = false) { self.recoversAfterFirstRequest = recoversAfterFirstRequest }
    var requested: Bool { lock.withLock { completion != nil } }
    func request(_ completion: @escaping @Sendable (TaskNotificationAuthorization) -> Void) {
        let (recovered, waiters) = lock.withLock {
            if recoversAfterFirstRequest, self.completion != nil { return (true, [CheckedContinuation<Void, Never>]()) }
            self.completion = completion
            let waiters = requestWaiters
            requestWaiters = []
            return (false, waiters)
        }
        waiters.forEach { $0.resume() }
        if recovered { completion(.authorized) }
    }
    func waitForRequest() async {
        await withCheckedContinuation { continuation in
            let requested = lock.withLock {
                if completion != nil { return true }
                requestWaiters.append(continuation)
                return false
            }
            if requested { continuation.resume() }
        }
    }
    func scheduleCleanupReply() -> Task<Void, Never> {
        Task {
            do { try await Task.sleep(nanoseconds: 2_000_000_000) }
            catch { return }
            reply(.authorized)
        }
    }
    func reply(_ value: TaskNotificationAuthorization) { lock.withLock { completion }?(value) }
}

@Test func notificationSettingsReadTimeoutReleasesReconciliationFileLeaseForLocalSave() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let native = ControlledNotificationSettings(recoversAfterFirstRequest: true)
    let center = SettingsReadNotificationCenter(native: native)
    let store = LocalTaskNotificationStore(directory: directory)
    let effect = SettingsReadNotificationEffect(center: center, store: store)
    let manager = TaskManager(replica: SettingsReadReplica(), postCommitEffects: effect)
    let startup = Task {
        await #expect(throws: NotificationSettingsReadError.self) {
            _ = try await manager.reconcileNotifications(center: center, store: store)
        }
    }
    await native.waitForRequest()
    let cleanup = native.scheduleCleanupReply()
    defer { cleanup.cancel() }
    let saved = try await manager.create(TaskDraft(description: "Local work survives unavailable notification settings"))
    _ = await startup.value
    #expect(try await manager.task(id: saved.id) == saved)
    #expect(await effect.report?.authorization == .authorized)
    #expect(await effect.error == nil)
    cleanup.cancel()
    await cleanup.value
}

private struct SettingsReadNotificationCenter: TaskNotificationCenter {
    let native: ControlledNotificationSettings
    func authorization() async throws -> TaskNotificationAuthorization {
        try await NotificationAuthorizationReader.read(timeoutNanoseconds: 50_000_000, request: native.request)
    }
    func requestAuthorization() -> TaskNotificationAuthorization {
        Issue.record("A read-only settings lookup must not request user authorization")
        return .unavailable
    }
    func pending() -> [PendingTaskNotification] { [] }
    func add(_ request: TaskNotificationRequest) { Issue.record("This undated task has no alert to schedule") }
    func remove(identifiers: [String]) {}
}

private actor SettingsReadNotificationEffect: TaskPostCommitEffect {
    let center: SettingsReadNotificationCenter
    let store: LocalTaskNotificationStore
    var report: TaskNotificationReport?
    var error: String?
    init(center: SettingsReadNotificationCenter, store: LocalTaskNotificationStore) { self.center = center; self.store = store }
    func apply(to manager: TaskManager, origin: TaskChangeOrigin) async {
        do { report = try await manager.reconcileNotifications(center: center, store: store) }
        catch { self.error = error.localizedDescription }
    }
}

private actor SettingsReadReplica: TaskReplica {
    private var records: [TaskRecord] = []
    func tasks() -> [TaskRecord] { records }
    func create(id: UUID, attributes: TaskAttributes) -> TaskRecord {
        let task = TaskRecord(id: id, attributes: attributes)
        records.append(task)
        return task
    }
    func update(id: UUID, changes: TaskAttributePatch) throws -> TaskRecord {
        throw TaskManagementError.taskNotFound(id)
    }
}
