import SwiftUI
import Observation
import TskCore
import TskNative

@MainActor
@Observable
final class SynchronizationOpportunities {
    private let manager: TaskManager
    private let connectivity = ConnectivityMonitor()
    @ObservationIgnored private var monitoring: Task<Void, Never>?
    var backgroundError: String?

    init(manager: TaskManager) { self.manager = manager }

    deinit { monitoring?.cancel() }

    func start() {
        guard monitoring == nil else { return }
        backgroundError = SynchronizationAppDelegate.schedulingError
        monitoring = Task { [manager, connectivity] in
            for await _ in connectivity.restorations() {
                await manager.requestSynchronization(trigger: .connectivityRestored)
            }
        }
    }

    func foreground() async {
        await manager.requestSynchronization(trigger: .appOpened)
    }

    func background() {
        SynchronizationAppDelegate.scheduleRefresh()
        backgroundError = SynchronizationAppDelegate.schedulingError
    }
}
