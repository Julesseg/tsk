import Foundation
import Observation
import TskCore
import TskNative

@MainActor @Observable final class SpotlightController {
    let store: TaskStore
    private(set) var status: TaskSpotlightIndexStatus?
    private(set) var error: String?
    private(set) var statusError: String?
    private(set) var isRefreshing = false
    private(set) var queryResult: String?
    private(set) var queryItems: [SpotlightIndexedItem] = []
    private(set) var fixtureResult: String?
    init(store: TaskStore) { self.store = store }
    func loadStatus() {
        do { status = try SpotlightTaskEffect.status(directory: store.directory); statusError = nil }
        catch { statusError = "Spotlight status could not be read: " + error.localizedDescription }
    }
    func observe() async {
        do {
            while !Task.isCancelled {
                loadStatus()
                try await Task.sleep(for: .milliseconds(500))
            }
        } catch {}
    }
    func reconcile(force: Bool = true) async {
        isRefreshing = true
        status = await SpotlightTaskEffect(directory: store.directory).reconcile(manager: store.manager, force: force)
        isRefreshing = false
        error = nil
    }
    #if DEBUG && targetEnvironment(simulator)
    func fixture(stale: Bool) async {
        do { if stale { fixtureResult = try await installStaleSpotlightFixture(store: store) } else { fixtureResult = try await writeSpotlightReceivedFixture(store: store) }; error = nil; loadStatus() }
        catch { fixtureResult = nil; self.error = error.localizedDescription }
    }
    #endif
    func query() async {
        isRefreshing = true
        queryResult = nil
        error = nil
        do {
            let index = CoreSpotlightTaskIndex(namespace: SpotlightTaskEffect.namespace(directory: store.directory))
            queryItems = try await index.query()
            queryResult = "Core Spotlight query returned \(queryItems.count) indexed task(s). This checks the index API, not the system search screen."
            error = nil
        } catch { queryResult = nil; self.error = "Spotlight query failed: " + error.localizedDescription }
        isRefreshing = false
    }
}
