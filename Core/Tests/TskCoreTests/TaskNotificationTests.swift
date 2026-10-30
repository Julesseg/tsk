import Foundation
import Testing
import TskCore

@Test func notificationsDeriveDistinctAndCombinedEventsWithoutChangingStoredTaskDates() async throws {
    let replica = TestReplica()
    let manager = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 1792100000) })
    let combined = try await manager.create(TaskDraft(description: "Review", attributes: ["scheduled": "1792108800", "due": "1792141200", "opaque": "keep"]))
    let separate = try await manager.create(TaskDraft(description: "Distinct", attributes: ["scheduled": "1792141200", "due": "1792144800"]))
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let plan = try await manager.notificationPlan(calendar: calendar)
    let review = try #require(plan.future.first { $0.taskID == combined.id })
    #expect(review.kind == .combined)
    #expect(review.fireDate == Date(timeIntervalSince1970: 1792141200))
    #expect(review.events.map(\.storedSeconds) == [1792108800, 1792141200])
    #expect(plan.future.filter { $0.taskID == separate.id }.count == 2)
    #expect(try await manager.task(id: combined.id) == combined)
    let disabled = try await manager.notificationPlan(preferences: TaskNotificationPreferences(midnightReplacement: false), calendar: calendar)
    #expect(disabled.future.filter { $0.taskID == combined.id }.map(\.fireDate) == [Date(timeIntervalSince1970: 1792108800), Date(timeIntervalSince1970: 1792141200)])
    #expect(try await manager.task(id: combined.id) == combined)
}

@Test(arguments: ["scheduled", "due"])
func midnightFallbackUsesCurrentDeviceZoneAndExplicitDSTResolutionWhileOtherTimesRemainAbsolute(attribute: String) throws {
    let parser = ISO8601DateFormatter()
    let id = UUID()
    func record(_ text: String, status: String = "pending") throws -> TaskRecord {
        TaskRecord(id: id, attributes: ["status": status, attribute: String(Int(try #require(parser.date(from: text)).timeIntervalSince1970))])
    }
    var paris = Calendar(identifier: .gregorian); paris.timeZone = TimeZone(identifier: "Europe/Paris")!
    let now = try #require(parser.date(from: "2026-01-01T00:00:00Z"))
    for (original, expected) in [("2026-03-28T23:00:00Z", "2026-03-29T01:00:00Z"), ("2026-10-24T22:00:00Z", "2026-10-25T00:30:00Z")] {
        let task = try record(original)
        let plan = try TaskManager.notificationPlan(tasks: [task], preferences: TaskNotificationPreferences(hour: 2, minute: 30), calendar: paris, at: now)
        #expect(plan.future.first?.fireDate == parser.date(from: expected))
        #expect(plan.future.first?.events.first?.storedSeconds == Int64(task.attributes[attribute]!))
    }
    let absolute = try record("2026-03-29T10:15:00Z")
    #expect(try TaskManager.notificationPlan(tasks: [absolute], calendar: paris, at: now).future.first?.fireDate == parser.date(from: "2026-03-29T10:15:00Z"))
    var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
    let midnight = try record("2026-03-29T00:00:00Z")
    #expect(try TaskManager.notificationPlan(tasks: [midnight], calendar: utc, at: now).future.first?.fireDate == parser.date(from: "2026-03-29T09:00:00Z"))
    #expect(try TaskManager.notificationPlan(tasks: [midnight], calendar: paris, at: now).future.first?.fireDate == parser.date(from: "2026-03-29T00:00:00Z"))
    let excluded = [try record("2026-03-29T10:00:00Z", status: "completed"), try record("2026-03-29T10:00:00Z", status: "deleted"), TaskRecord(id: UUID(), attributes: ["status": "recurring", "due": "1792144800", "recur": "daily"])]
    #expect(try TaskManager.notificationPlan(tasks: excluded, calendar: paris, at: now).future.isEmpty)
}

private struct NotificationTestLease: TaskMutationLease { func release() {} }
private actor NotificationTestState: TaskNotificationStateStore {
    var state = TaskNotificationState()
    func acquireLease() -> any TaskMutationLease { NotificationTestLease() }
    func load() -> TaskNotificationState { state }
    func save(_ state: TaskNotificationState) { self.state = state }
}
private actor NotificationPolicyCenter: TaskNotificationCenter {
    var permission = TaskNotificationAuthorization.authorized
    var requests: [String: TaskNotificationRequest] = [:]
    var outdated = Set<String>()
    var additions = 0
    let capacity: Int
    let revokeAfterAdd: Bool
    init(capacity: Int, revokeAfterAdd: Bool = false) { self.capacity = capacity; self.revokeAfterAdd = revokeAfterAdd }
    func authorization() -> TaskNotificationAuthorization { permission }
    func requestAuthorization() -> TaskNotificationAuthorization { permission }
    func pending() -> [PendingTaskNotification] { requests.values.map { PendingTaskNotification(identifier: $0.identifier, request: $0, nextTriggerDate: $0.fireDate, contentMatchesRequest: !outdated.contains($0.identifier)) } }
    func add(_ request: TaskNotificationRequest) throws {
        guard permission.permitsAlerts else { throw TaskManagementError.storage("Permission revoked") }
        guard requests.count < capacity || requests[request.identifier] != nil else { throw TaskManagementError.storage("Registration capacity reached") }
        requests[request.identifier] = request
        outdated.remove(request.identifier)
        additions += 1
        if revokeAfterAdd { permission = .denied }
    }
    func remove(identifiers: [String]) { for id in identifiers { requests[id] = nil } }
    func deny() { permission = .denied }
    func markOutdated() { outdated = Set(requests.keys) }
    func additionCount() -> Int { additions }
}

@Test func notificationReconciliationRetainsNearestReadBackAlertsAndCancelsKnownLocalChanges() async throws {
    let manager = TaskManager(replica: TestReplica(), now: { Date(timeIntervalSince1970: 1792100000) })
    let state = NotificationTestState()
    let center = NotificationPolicyCenter(capacity: 2)
    let first = try await manager.create(TaskDraft(description: "First", attributes: ["due": "1792141200"]))
    let second = try await manager.create(TaskDraft(description: "Second", attributes: ["due": "1792144800"]))
    _ = try await manager.create(TaskDraft(description: "Third", attributes: ["due": "1792148400"]))
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let limited = try await manager.reconcileNotifications(center: center, store: state, calendar: calendar)
    #expect(limited.registered.map(\.taskID) == [first.id, second.id])
    #expect(limited.unscheduled.count == 1)
    #expect(!limited.errors.isEmpty)
    _ = try await manager.complete(id: first.id)
    _ = try await manager.update(id: second.id, changes: ["due": "1792152000"])
    let changed = try await manager.reconcileNotifications(center: center, store: state, calendar: calendar)
    #expect(!changed.registered.contains { $0.taskID == first.id })
    #expect(changed.registered.first { $0.taskID == second.id }?.fireDate == Date(timeIntervalSince1970: 1792152000))
    await center.deny()
    let denied = try await manager.reconcileNotifications(center: center, store: state, calendar: calendar)
    #expect(denied.authorization == .denied)
    #expect(denied.registered.isEmpty)
    #expect(await center.pending().isEmpty)
    _ = try await manager.create(TaskDraft(description: "Permission does not block task management"))
}

private final class NotificationTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var instant: Date
    init(_ seconds: Double) { instant = Date(timeIntervalSince1970: seconds) }
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return instant }
    func set(_ seconds: Double) { lock.lock(); instant = Date(timeIntervalSince1970: seconds); lock.unlock() }
}

@Test func changingMidnightPreferencesCannotRepeatAnOriginalEventAfterItsAcceptedDeliveryOpportunity() async throws {
    let clock = NotificationTestClock(1000)
    let manager = TaskManager(replica: TestReplica(), now: { clock.now() })
    let state = NotificationTestState()
    let center = NotificationPolicyCenter(capacity: 100)
    _ = try await manager.create(TaskDraft(description: "Combined", attributes: ["scheduled": "0", "due": "32400"]))
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let initial = try await manager.reconcileNotifications(center: center, store: state, calendar: calendar)
    #expect(initial.registered.first?.kind == .combined)
    clock.set(40000)
    await center.remove(identifiers: initial.registered.map(\.identifier))
    try await manager.saveNotificationPreferences(TaskNotificationPreferences(hour: 12), using: state)
    let changed = try await manager.reconcileNotifications(center: center, store: state, calendar: calendar)
    #expect(changed.registered.isEmpty)
    #expect(changed.unscheduled.isEmpty)
    #expect(try await manager.notificationState(using: state).accepted.count == 2)
}

@Test func permissionRevokedDuringRegistrationIsReadBackAndCancelsTheAcceptedPendingAlert() async throws {
    let manager = TaskManager(replica: TestReplica(), now: { Date(timeIntervalSince1970: 1792100000) })
    _ = try await manager.create(TaskDraft(description: "Revoked during IPC", attributes: ["due": "1792141200"]))
    let center = NotificationPolicyCenter(capacity: 10, revokeAfterAdd: true)
    let state = NotificationTestState()
    let report = try await manager.reconcileNotifications(center: center, store: state)
    #expect(report.authorization == .denied)
    #expect(report.registered.isEmpty)
    #expect(await center.pending().isEmpty)
    #expect(try await manager.notificationState(using: state).accepted.isEmpty)
}

@Test func notificationReconciliationRefreshesOutdatedContentWithoutRepeatingAcceptedEvents() async throws {
    let manager = TaskManager(replica: TestReplica(), now: { Date(timeIntervalSince1970: 1792100000) })
    let state = NotificationTestState()
    let center = NotificationPolicyCenter(capacity: 10)
    _ = try await manager.create(TaskDraft(description: "Existing alert", attributes: ["due": "1792141200"]))
    let original = try await manager.reconcileNotifications(center: center, store: state)
    let accepted = try await manager.notificationState(using: state).accepted
    await center.markOutdated()
    let refreshed = try await manager.reconcileNotifications(center: center, store: state)
    #expect(refreshed.registered == original.registered)
    #expect(refreshed.errors.isEmpty)
    #expect(await center.additionCount() == 2)
    let current = try await manager.notificationState(using: state).accepted
    #expect(current.map(\.event) == accepted.map(\.event))
    #expect(current.map(\.acceptedAt) == accepted.map(\.acceptedAt))
    _ = try await manager.reconcileNotifications(center: center, store: state)
    #expect(await center.additionCount() == 2)
}
