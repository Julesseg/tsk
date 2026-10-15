@preconcurrency import BackgroundTasks
import UIKit
import TskCore
import TskNative

@MainActor
final class SynchronizationAppDelegate: NSObject, UIApplicationDelegate {
    static var schedulingError: String?
    static var refreshIdentifier: String { (Bundle.main.bundleIdentifier ?? "com.julesseguin.tsk") + ".refresh" }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshIdentifier, using: .main) { task in
            Task { @MainActor in
                await Self.refresh(task)
            }
        }
        if !registered { Self.schedulingError = "iOS did not register background synchronization. Foreground synchronization remains available." }
        return true
    }

    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            schedulingError = nil
        } catch {
            schedulingError = "Background synchronization is unavailable: \(error.localizedDescription). Changes and app opening still trigger synchronization."
        }
    }

    private static func refresh(_ task: BGTask) async {
        scheduleRefresh()
        let execution = BackgroundSynchronizationExecution()
        task.expirationHandler = { Task { @MainActor in await execution.expire() } }
        do {
            let directory = try TaskChampionSession.directory(testName: ProcessInfo.processInfo.environment["TSK_TEST_REPLICA_NAME"])
            let manager = try await TaskChampionSession.open(directory: directory)
            execution.manager = manager
            guard !execution.expired else {
                await manager.suspendSynchronization()
                task.setTaskCompleted(success: false)
                return
            }
            let continuous: ContinuousReminderController
            if let current = ContinuousReminderController.current, current.store.directory == directory { continuous = current }
            else { continuous = ContinuousReminderController(store: TaskStore(manager: manager, directory: directory)) }
            execution.continuousReminders = continuous
            await continuous.scan()
            guard !execution.expired else { task.setTaskCompleted(success: false); return }
            let importSucceeded = continuous.error == nil && !continuous.isRunning && (continuous.status?.active != true || continuous.result?.stopped != true)
            if await manager.synchronizationStatus() == .localOnly {
                task.setTaskCompleted(success: importSucceeded)
                return
            }
            _ = try await manager.synchronize(trigger: .backgroundOpportunity)
            task.setTaskCompleted(success: importSucceeded)
        } catch { task.setTaskCompleted(success: false) }
    }
}

@MainActor
private final class BackgroundSynchronizationExecution {
    var manager: TaskManager?
    var expired = false
    var continuousReminders: ContinuousReminderController?

    func expire() async {
        expired = true
        continuousReminders?.cancel()
        await continuousReminders?.store.manager.suspendSynchronization()
        await manager?.suspendSynchronization()
    }
}
