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
        do {
            let directory = TaskChampionSession.directory(testName: ProcessInfo.processInfo.environment["TSK_TEST_REPLICA_NAME"])
            let manager = try await TaskChampionSession.open(directory: directory)
            task.expirationHandler = { Task { await manager.suspendSynchronization() } }
            if await manager.synchronizationStatus() == .localOnly {
                task.setTaskCompleted(success: true)
                return
            }
            _ = try await manager.synchronize(trigger: .backgroundOpportunity)
            task.setTaskCompleted(success: true)
        } catch { task.setTaskCompleted(success: false) }
    }
}
