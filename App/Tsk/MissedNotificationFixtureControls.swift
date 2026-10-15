#if DEBUG
import SwiftUI
import TskCore
import TskNative

private struct MissedNotificationEvidence: Codable {
    let token: UUID
    let learned: TaskRecord
    let completed: TaskRecord
    let deleted: TaskRecord
    let future: TaskRecord
    let locallyKnown: TaskRecord
    var initialReceipt: TaskSynchronizationReceipt
    var finalReceipt: TaskSynchronizationReceipt?
    var accepted: [TaskNotificationAcceptance]
    var delivered: [String] = []
    var deliveredDates: [String: Date] = [:]
    var pending: [String] = []
    var repeated = false
    var cancellationVerified = false
    var errors: [String] = []
}

struct MissedNotificationFixtureControls: View {
    let controller: TaskNotificationController
    @State private var result = "Not run"
    @State private var busy = false
    private var token: UUID? {
        #if targetEnvironment(simulator)
        let environment = ProcessInfo.processInfo.environment
        guard environment["TSK_UI_ISOLATED_SIMULATOR"] == "1", let token = environment["TSK_TEST_MISSED_NOTIFICATION_FIXTURE"] else { return nil }
        return UUID(uuidString: token)
        #else
        return nil
        #endif
    }
    var body: some View {
        if let token {
            Section("Disposable encrypted missed-alert verification") {
                Text(result).accessibilityIdentifier("missed-fixture-result")
                Button("Sync genuine missed and final-state peer tasks") { run { try await prepare(token) } }.accessibilityIdentifier("missed-fixture-sync")
                Button("Read actual delivered missed alert") { run { try await delivered(token) } }.accessibilityIdentifier("missed-fixture-delivered")
                Button("Repeat sync after reopen without resending") { run { try await repeated(token) } }.accessibilityIdentifier("missed-fixture-repeat")
                Button("Receive remote completion and cancel future alert") { run { try await cancel(token) } }.accessibilityIdentifier("missed-fixture-cancel")
            }.disabled(busy)
        }
    }
    private func configuration() throws -> SyncConfiguration {
        let environment = ProcessInfo.processInfo.environment
        guard let url = environment["TSK_UI_SYNC_SERVER_URL"], let rawClient = environment["TSK_UI_MISSED_CLIENT_ID"], let client = UUID(uuidString: rawClient), let secret = environment["TSK_UI_SYNC_SECRET"] else { throw TaskManagementError.storage("The real isolated missed-alert server is unavailable.") }
        return try SyncConfiguration(serverURL: url, clientID: client, encryptionSecret: secret)
    }
    private func file(_ token: UUID) -> URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("notifications-fixture-missed-\(token.uuidString).json") }
    private func load(_ token: UUID) throws -> MissedNotificationEvidence { try JSONDecoder().decode(MissedNotificationEvidence.self, from: Data(contentsOf: file(token))) }
    private func save(_ evidence: MissedNotificationEvidence) throws { try JSONEncoder().encode(evidence).write(to: file(evidence.token), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
    private func run(_ operation: @escaping @MainActor () async throws -> String) {
        busy = true
        Task {
            do { result = try await operation() }
            catch {
                result = "FAILED: " + error.localizedDescription
                if let token, var evidence = try? load(token) { evidence.errors.append(error.localizedDescription); try? save(evidence) }
            }
            busy = false
            await controller.refresh()
        }
    }
    private func peer(_ token: UUID) -> TaskChampionReplica { TaskChampionReplica(directory: controller.store.directory.appendingPathComponent("missed-peer-\(token.uuidString)")) }
    private func receipt() async throws -> TaskSynchronizationReceipt {
        guard let success = try await LocalTaskSynchronizationReceiptStore(directory: controller.store.directory).load()?.success else { throw TaskManagementError.storage("There is no immutable final successful receipt.") }
        return success
    }
    private func prepare(_ token: UUID) async throws -> String {
        guard !FileManager.default.fileExists(atPath: file(token).path) else { throw TaskManagementError.storage("This fixture is already seeded. Use the repeat check.") }
        guard try await UNTaskNotificationCenter().authorization().permitsAlerts else { throw TaskManagementError.storage("Allow actual notification permission first.") }
        let configuration = try configuration()
        let manager = controller.store.manager
        await manager.configureSynchronization(nil)
        let past = String(Int64(Date().timeIntervalSince1970) - 3600)
        let local = try await manager.create(TaskDraft(description: "Locally known missed \(token)", attributes: ["due": past]))
        let peer = peer(token)
        let learned = try await peer.create(id: UUID(), attributes: ["status": "pending", "description": "New remote missed \(token)", "scheduled": past, "due": past, "foreign_é": "one", "foreign_e\u{301}": "two"])
        let completed = try await peer.create(id: UUID(), attributes: ["status": "completed", "description": "Same sync completed \(token)", "due": past])
        let deleted = try await peer.create(id: UUID(), attributes: ["status": "deleted", "description": "Same sync deleted \(token)", "due": past])
        let future = try await peer.create(id: UUID(), attributes: ["status": "pending", "description": "Remote future \(token)", "due": String(Int64(Date().timeIntervalSince1970) + 7200)])
        try await peer.synchronize(using: configuration)
        try await SyncConfigurationStore(directory: controller.store.directory).save(configuration)
        _ = try await manager.synchronize(using: configuration)
        let state = try await manager.notificationState(using: LocalTaskNotificationStore(directory: controller.store.directory))
        let accepted = state.accepted.filter { $0.immediate == true }
        guard Set(accepted.map(\.event)) == Set([TaskNotificationEvent(taskID: learned.id, source: .planned, storedSeconds: Int64(past)!), TaskNotificationEvent(taskID: learned.id, source: .due, storedSeconds: Int64(past)!)]), state.pendingMissed?.isEmpty != false, state.attemptingMissed?.isEmpty != false else { throw TaskManagementError.storage("The genuine final snapshot did not accept exactly the new missed constituents.") }
        let snapshot = try await receipt()
        guard snapshot.tasks.contains(learned), snapshot.tasks.contains(completed), snapshot.tasks.contains(deleted), try await manager.task(id: learned.id) == learned else { throw TaskManagementError.storage("The final successful snapshot or raw task identity was changed.") }
        let pending = try await UNTaskNotificationCenter().pending()
        guard pending.contains(where: { $0.request?.taskID == future.id }) else { throw TaskManagementError.storage("The actual future request is missing.") }
        let evidence = MissedNotificationEvidence(token: token, learned: learned, completed: completed, deleted: deleted, future: future, locallyKnown: local, initialReceipt: snapshot, accepted: accepted, pending: pending.map(\.identifier))
        try save(evidence)
        return "SYNCED missed=2 completed=0 deleted=0 local=0"
    }
    private func delivered(_ token: UUID) async throws -> String {
        var evidence = try load(token)
        let center = UNTaskNotificationCenter()
        let limit = ContinuousClock.now.advanced(by: .seconds(15))
        var delivered = try await center.delivered()
        while !delivered.contains(where: { $0.taskID == evidence.learned.id }), ContinuousClock.now < limit {
            try await Task.sleep(for: .milliseconds(200))
            delivered = try await center.delivered()
        }
        let own = Set([evidence.learned.id, evidence.completed.id, evidence.deleted.id, evidence.locallyKnown.id])
        let matching = delivered.filter { own.contains($0.taskID) }
        guard matching.count == 1, matching[0].taskID == evidence.learned.id, matching[0].kind == .combined else { throw TaskManagementError.storage("Actual delivered readback did not contain exactly the learned combined missed alert.") }
        evidence.delivered = matching.map(\.immediateIdentifier)
        let native = await center.deliveredNotifications().filter { evidence.delivered.contains($0.identifier) }
        evidence.deliveredDates = Dictionary(uniqueKeysWithValues: native.map { ($0.identifier, $0.deliveredAt) })
        try save(evidence)
        return "DELIVERED missed=1 suppressed=3"
    }
    private func repeated(_ token: UUID) async throws -> String {
        var evidence = try load(token)
        let before = try await controller.store.manager.notificationState(using: LocalTaskNotificationStore(directory: controller.store.directory))
        _ = try await controller.store.manager.synchronize(using: configuration())
        let after = try await controller.store.manager.notificationState(using: LocalTaskNotificationStore(directory: controller.store.directory))
        let accepted = after.accepted.filter { $0.immediate == true }
        guard accepted.count == 2, accepted.map(\.acceptedAt) == before.accepted.filter({ $0.immediate == true }).map(\.acceptedAt), after.pendingMissed?.isEmpty != false, after.attemptingMissed?.isEmpty != false else { throw TaskManagementError.storage("Repeated sync changed the original acceptance ledger.") }
        evidence.finalReceipt = try await receipt()
        guard evidence.finalReceipt?.id != evidence.initialReceipt.id else { throw TaskManagementError.storage("No new final successful boundary was recorded.") }
        try await Task.sleep(for: .milliseconds(500))
        let actual = await UNTaskNotificationCenter().deliveredNotifications().filter { evidence.delivered.contains($0.identifier) }
        guard !evidence.deliveredDates.isEmpty, actual.count == evidence.deliveredDates.count,
              actual.allSatisfy({ evidence.deliveredDates[$0.identifier] == $0.deliveredAt }) else { throw TaskManagementError.storage("Actual delivered timestamps changed or could not be verified after repeated synchronization.") }
        evidence.accepted = accepted; evidence.repeated = true
        try save(evidence)
        return "REPEATED accepted=2 no-resubmission"
    }
    private func cancel(_ token: UUID) async throws -> String {
        var evidence = try load(token)
        let peer = peer(token)
        _ = try await peer.update(id: evidence.future.id, changes: ["status": "completed"])
        try await peer.synchronize(using: configuration())
        _ = try await controller.store.manager.synchronize(using: configuration())
        let pending = try await UNTaskNotificationCenter().pending()
        guard !pending.contains(where: { $0.request?.taskID == evidence.future.id }), try await controller.store.manager.task(id: evidence.future.id).status == "completed" else { throw TaskManagementError.storage("Received remote completion did not cancel the pending future alert.") }
        evidence.pending = pending.map(\.identifier); evidence.cancellationVerified = true
        try save(evidence)
        return "CANCELED remote future after sync"
    }
}
#endif
