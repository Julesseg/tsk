import Foundation
import Observation
import TskCore
import TskNative

@MainActor @Observable final class SpotlightController {
    let store: TaskStore
    private(set) var status: TaskSpotlightIndexStatus?
    private(set) var error: String?
    private(set) var isRefreshing = false
    private(set) var queryResult: String?
    private(set) var fixtureResult: String?
    init(store: TaskStore) { self.store = store }
    func loadStatus() {
        do { status = try SpotlightTaskEffect.status(directory: store.directory); error = nil }
        catch { self.error = "Spotlight status could not be read: " + error.localizedDescription }
    }
    func reconcile() async {
        isRefreshing = true
        status = await SpotlightTaskEffect(directory: store.directory).reconcile(manager: store.manager)
        isRefreshing = false
        error = nil
    }
    #if DEBUG && targetEnvironment(simulator)
    func fixture(stale: Bool) async {
        do { fixtureResult = try await (stale ? installStaleSpotlightFixture(store: store) : writeSpotlightReceivedFixture(store: store)); error = nil; loadStatus() }
        catch { fixtureResult = nil; self.error = error.localizedDescription }
    }
    #endif
    func query() async {
        isRefreshing = true
        do {
            let index = CoreSpotlightTaskIndex(namespace: SpotlightTaskEffect.namespace(directory: store.directory))
            queryResult = "Core Spotlight query returned \(try await index.query().count) indexed task(s). This checks the index API, not the system search screen."
            error = nil
        } catch { queryResult = nil; self.error = "Spotlight query failed: " + error.localizedDescription }
        isRefreshing = false
    }
}
