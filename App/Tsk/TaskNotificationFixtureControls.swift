#if DEBUG
import SwiftUI
import TskCore
import TskNative
import AppIntents

private struct NotificationFixtureEvidence: Codable {
    var task: TaskRecord?
    var fireDate: Date?
    var registered: [String] = []
    var delivered: [String] = []
    var capacityAttempts: [String] = []
    var capacityRetained: [String] = []
    var mutationVerified = false
    var deniedTask: TaskRecord?
    var midnightTask: TaskRecord?
    var midnightRegisteredDate: Date?
    var errors: [String] = []
}

struct TaskNotificationFixtureControls: View {
    let controller: TaskNotificationController
    @State private var result = "Not run"
    @State private var busy = false
    private var token: String? {
        #if targetEnvironment(simulator)
        let environment = ProcessInfo.processInfo.environment
        guard environment["TSK_UI_ISOLATED_SIMULATOR"] == "1", let token = environment["TSK_TEST_NOTIFICATION_FIXTURE"], UUID(uuidString: token) != nil else { return nil }
        return token
        #else
        return nil
        #endif
    }
    var body: some View {
        if let token {
            Section("Disposable notification verification") {
                Text(result).accessibilityIdentifier("notification-fixture-result")
                Button("Verify midnight preference registration") { run(token: token) { try await midnight(token) } }.accessibilityIdentifier("notification-fixture-midnight")
                Button("Register fresh closed-app alert") { run(token: token) { try await register(token) } }.accessibilityIdentifier("notification-fixture-register")
                Button("Read delivered alerts without reseeding") { run(token: token) { try await delivered(token) } }.accessibilityIdentifier("notification-fixture-delivered")
                Button("Probe actual registration capacity") { run(token: token) { try await capacity(token) } }.accessibilityIdentifier("notification-fixture-capacity")
                Button("Verify saved date change and completion") { run(token: token) { try await mutation(token) } }.accessibilityIdentifier("notification-fixture-mutation")
                Button("Verify denied permission preserves tasks") { run(token: token) { try await denied(token) } }.accessibilityIdentifier("notification-fixture-denied")
                Link("Open system notification settings", destination: URL(string: UIApplication.openNotificationSettingsURLString)!).accessibilityIdentifier("notification-fixture-system-settings")
            }.disabled(busy)
        }
    }
    private func file(_ token: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("notifications-fixture-\(token).json")
    }
    private func load(_ token: String) throws -> NotificationFixtureEvidence {
        do { return try JSONDecoder().decode(NotificationFixtureEvidence.self, from: Data(contentsOf: file(token))) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return NotificationFixtureEvidence() }
    }
    private func save(_ evidence: NotificationFixtureEvidence, _ token: String) throws { try JSONEncoder().encode(evidence).write(to: file(token), options: .atomic) }
    private func run(token: String, operation: @escaping @MainActor () async throws -> String) {
        busy = true
        Task {
            do { result = try await operation() }
            catch {
                result = "FAILED: " + error.localizedDescription
                if var evidence = try? load(token) { evidence.errors.append(error.localizedDescription); try? save(evidence, token) }
            }
            busy = false
            await controller.refresh()
        }
    }
    private func midnight(_ token: String) async throws -> String {
        var evidence = try load(token)
        let manager = controller.store.manager
        let task: TaskRecord
        if let saved = evidence.midnightTask { task = saved }
        else {
            let calendar = Calendar.autoupdatingCurrent
            let date = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 2, to: Date())!)
            task = try await manager.create(TaskDraft(description: "Midnight notification " + token, attributes: ["due": String(Int64(date.timeIntervalSince1970)), "foreign_alert": "midnight unchanged"]))
            evidence.midnightTask = task
        }
        guard try await manager.task(id: task.id) == task else { throw TaskManagementError.storage("Alert preferences changed stored task attributes.") }
        let state = try await manager.notificationState(using: LocalTaskNotificationStore(directory: controller.store.directory))
        let expected = try await manager.notificationPlan(preferences: state.preferences).future.first { $0.taskID == task.id }
        let actual = try await UNTaskNotificationCenter().pending().first { $0.request?.taskID == task.id }
        guard let expected, actual?.request == expected, actual?.nextTriggerDate == expected.fireDate else { throw TaskManagementError.storage("Actual midnight registration does not match saved preferences.") }
        evidence.midnightRegisteredDate = expected.fireDate
        try save(evidence, token)
        return "MIDNIGHT enabled=\(state.preferences.midnightReplacement) hour=\(state.preferences.hour) minute=\(state.preferences.minute)"
    }
    private func register(_ token: String) async throws -> String {
        var evidence = try load(token)
        guard evidence.task == nil else { throw TaskManagementError.storage("This fixture already registered an alert. Read it back without reseeding.") }
        guard try await UNTaskNotificationCenter().authorization().permitsAlerts else { throw TaskManagementError.storage("Allow actual notification permission first.") }
        let fire = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) + 45)
        let seconds = String(Int64(fire.timeIntervalSince1970))
        let task = try await controller.store.manager.create(TaskDraft(description: "Closed-app notification " + token, attributes: ["scheduled": seconds, "due": seconds, "foreign_alert": "preserve"]))
        let pending = try await UNTaskNotificationCenter().pending().filter { $0.request?.taskID == task.id }
        guard pending.count == 1, pending[0].request?.kind == .combined, pending[0].nextTriggerDate == fire else { throw TaskManagementError.storage("Actual pending readback did not contain the exact combined alert.") }
        evidence.task = task; evidence.fireDate = fire; evidence.registered = pending.map(\.identifier)
        try save(evidence, token)
        return "REGISTERED \(Int(fire.timeIntervalSince1970))"
    }
    private func delivered(_ token: String) async throws -> String {
        var evidence = try load(token)
        guard let fire = evidence.fireDate, Date() > fire, !evidence.registered.isEmpty else { throw TaskManagementError.storage("No prior alert is ready for delivered readback.") }
        let ids = await UNTaskNotificationCenter().deliveredIdentifiers()
        evidence.delivered = evidence.registered.filter(ids.contains)
        try save(evidence, token)
        guard evidence.delivered.count == evidence.registered.count else { throw TaskManagementError.storage("iOS did not return the registered alert in delivered notifications.") }
        return "DELIVERED \(evidence.delivered.count)"
    }
    private func capacity(_ token: String) async throws -> String {
        var evidence = try load(token)
        guard try await UNTaskNotificationCenter().authorization().permitsAlerts else { throw TaskManagementError.storage("Actual notification permission is required.") }
        let base = Int64(Date().timeIntervalSince1970) + 7200
        let tasks = (0..<100).map { index in TaskRecord(id: UUID(), attributes: ["description": "Capacity \(token) \(index)", "status": "pending", "due": String(base + Int64(index * 60))]) }
        let requests = try TaskManager.notificationPlan(tasks: tasks, preferences: TaskNotificationPreferences(midnightReplacement: false), at: Date()).future
        let center = UNTaskNotificationCenter()
        evidence.capacityAttempts = []
        for request in requests {
            do { try await center.add(request); evidence.capacityAttempts.append("accepted " + request.identifier) }
            catch { evidence.capacityAttempts.append("error \(request.identifier): \(error.localizedDescription)") }
        }
        let owned = Set(requests.map(\.identifier))
        evidence.capacityRetained = try await center.pending().map(\.identifier).filter(owned.contains).sorted()
        try save(evidence, token)
        await center.remove(identifiers: requests.map(\.identifier))
        return "CAPACITY attempted=\(requests.count) retained=\(evidence.capacityRetained.count)"
    }
    private func mutation(_ token: String) async throws -> String {
        var evidence = try load(token)
        let base = Int64(Date().timeIntervalSince1970) + 7200
        let task = try await controller.store.manager.create(TaskDraft(description: "Notification mutation " + token, attributes: ["due": String(base), "foreign_alert": "preserve"]))
        _ = try await RescheduleTaskIntent(task: IntentTaskEntity(task), role: .deadline, date: Date(timeIntervalSince1970: Double(base + 3600)), directory: controller.store.directory).perform()
        let changed = try await controller.store.manager.task(id: task.id)
        let center = UNTaskNotificationCenter()
        let pending = try await center.pending().filter { $0.request?.taskID == task.id }
        guard pending.count == 1, pending[0].nextTriggerDate == Date(timeIntervalSince1970: Double(base + 3600)), changed.attributes["foreign_alert"] == "preserve" else { throw TaskManagementError.storage("A saved date change was not reflected in actual pending notifications.") }
        _ = try await CompleteTaskIntent(task: IntentTaskEntity(changed), directory: controller.store.directory).perform()
        guard try await center.pending().allSatisfy({ $0.request?.taskID != task.id }), try await controller.store.manager.task(id: task.id).status == "completed" else { throw TaskManagementError.storage("Completion did not cancel the actual pending notification.") }
        evidence.mutationVerified = true
        try save(evidence, token)
        return "MUTATION VERIFIED"
    }
    private func denied(_ token: String) async throws -> String {
        var evidence = try load(token)
        guard try await UNTaskNotificationCenter().authorization() == .denied else { throw TaskManagementError.storage("Disable actual system permission before this check.") }
        let task = try await controller.store.manager.create(TaskDraft(description: "Denied permission task " + token, attributes: ["due": String(Int64(Date().timeIntervalSince1970) + 7200)]))
        guard try await controller.store.manager.task(id: task.id) == task else { throw TaskManagementError.storage("The denied-permission task was not durable.") }
        evidence.deniedTask = task
        try save(evidence, token)
        return "DENIED TASK SAVED"
    }
}
#endif
