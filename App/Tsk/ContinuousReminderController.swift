import Foundation
import Observation
import TskCore
import TskNative

@MainActor @Observable
final class ContinuousReminderController {
    static weak var current: ContinuousReminderController?
    let store: TaskStore
    let source = EventKitReminderSource()
    var status: ContinuousReminderStatus?
    var result: ReminderMoveResult?
    var error: String?
    var isRunning = false
    var fixtureWaiting = false
    @ObservationIgnored private var execution: Task<ReminderMoveResult?, any Error>?
    @ObservationIgnored private var debounce: Task<Void, Never>?
    #if DEBUG
    @ObservationIgnored private var fixtureContinuation: CheckedContinuation<Void, any Error>?
    #endif

    init(store: TaskStore) {
        self.store = store
        Self.current = self
        #if DEBUG && targetEnvironment(simulator)
        let environment = ProcessInfo.processInfo.environment
        if environment["TSK_UI_ISOLATED_SIMULATOR"] == "1", environment["TSK_TEST_REMINDERS_PAUSE_REMOVAL"] == "1" {
            source.fixtureBeforeRemoval = { [weak self] in try await self?.waitForFixture() }
        }
        #endif
    }

    deinit { execution?.cancel(); debounce?.cancel() }

    func load() async {
        do { status = try await store.manager.continuousReminderStatus() }
        catch { self.error = error.localizedDescription }
    }

    func enable(mappings: [ReminderListMapping]) async throws {
        try await store.manager.configureContinuousReminders(enabled: true, mappings: mappings)
        await load()
        SynchronizationAppDelegate.scheduleRefresh()
        await scan(retry: true)
    }

    func disable() async throws {
        cancel()
        try await store.manager.configureContinuousReminders(enabled: false, mappings: status?.configuration?.mappings ?? [])
        await load()
    }

    func scan(retry: Bool = false) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false; execution = nil }
        let manager = store.manager, source = source
        let task = Task { try await manager.runContinuousReminderImport(from: source, retry: retry) }
        execution = task
        do {
            if let next = try await task.value {
                if result == nil || !next.imported.isEmpty || next.stopped { result = next }
                error = nil
                if !next.imported.isEmpty { await store.reload() }
            }
        } catch { self.error = error.localizedDescription }
        await load()
    }

    func sourceChanged() {
        guard !isRunning, status?.active == true, status?.paused != true else { return }
        debounce?.cancel()
        debounce = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)); await self?.scan() }
            catch {}
        }
    }

    func cancel() {
        execution?.cancel()
        debounce?.cancel()
        #if DEBUG
        fixtureContinuation?.resume(throwing: CancellationError()); fixtureContinuation = nil; fixtureWaiting = false
        #endif
    }

    #if DEBUG
    private func waitForFixture() async throws {
        fixtureWaiting = true
        defer { fixtureWaiting = false; fixtureContinuation = nil }
        try await withCheckedThrowingContinuation { fixtureContinuation = $0 }
        try Task.checkCancellation()
    }

    func resumeFixture() { fixtureContinuation?.resume(); fixtureContinuation = nil }
    #endif
}
