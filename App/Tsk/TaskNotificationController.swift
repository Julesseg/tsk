import Foundation
import Observation
import TskCore
import TskNative

@MainActor @Observable
final class TaskNotificationController {
    let store: TaskStore
    var preferences = TaskNotificationPreferences()
    var report: TaskNotificationReport?
    var error: String?
    var isWorking = false
    private var queued = false
    init(store: TaskStore) { self.store = store }
    var needsAttention: Bool {
        error != nil || !(report?.errors.isEmpty ?? true) || !(report?.unscheduled.isEmpty ?? true) || !(report?.invalidTaskIDs.isEmpty ?? true)
    }
    func observe() async {
        do {
            for try await _ in await store.manager.changeUpdates() {
                if Task.isCancelled { return }
                await refresh()
            }
        } catch { self.error = error.localizedDescription }
    }
    func refresh() async {
        if isWorking { queued = true; return }
        isWorking = true
        defer { isWorking = false }
        repeat {
            queued = false
            do {
                report = try await TaskNotificationEffect.reconcile(manager: store.manager, directory: store.directory)
                preferences = try await store.manager.notificationState(using: LocalTaskNotificationStore(directory: store.directory)).preferences
                error = try TaskNotificationEffect.warning(directory: store.directory)
            } catch { self.error = error.localizedDescription }
        } while queued && !Task.isCancelled
    }
    func requestPermission() async {
        do { _ = try await UNTaskNotificationCenter().requestAuthorization() }
        catch { self.error = error.localizedDescription; return }
        await refresh()
    }
    func save(_ preferences: TaskNotificationPreferences) async {
        do { try await store.manager.saveNotificationPreferences(preferences, using: LocalTaskNotificationStore(directory: store.directory)) }
        catch { self.error = error.localizedDescription; return }
        await refresh()
    }
}
