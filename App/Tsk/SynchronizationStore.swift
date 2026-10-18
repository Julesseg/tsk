import Foundation
import Observation
import TskCore
import TskNative

@MainActor @Observable
final class SynchronizationStore {
    private let manager: TaskManager
    private let configurationStore: SyncConfigurationStore
    @ObservationIgnored private var observation: Task<Void, Never>?
    var configuration: SyncConfiguration?
    var state: SynchronizationState = .localOnly
    var isSaving = false
    var configurationError: String?

    init(manager: TaskManager, directory: URL) {
        self.manager = manager
        configurationStore = SyncConfigurationStore(directory: directory)
    }

    deinit { observation?.cancel() }

    var isSyncing: Bool { state == .syncing }
    var lastSynchronized: Date? {
        if case .synchronized(let date) = state { return date }
        return nil
    }
    var error: String? {
        get {
            if let configurationError { return configurationError }
            if case .failed(let message) = state { return message }
            return nil
        }
        set { configurationError = newValue }
    }
    var status: String {
        if error != nil { return "Synchronization needs attention" }
        switch state {
        case .localOnly: return "Local tasks only"
        case .ready: return "Ready to synchronize"
        case .pending: return "Saved locally · waiting to synchronize"
        case .syncing: return "Saved locally · synchronizing…"
        case .synchronized: return "Synchronized with server"
        case .failed: return "Synchronization needs attention"
        }
    }

    func startObserving(tasks: TaskStore) {
        guard observation == nil else { return }
        observation = Task { [weak self, manager] in
            let updates = await manager.synchronizationUpdates()
            for await state in updates {
                guard let self else { return }
                self.state = state
                if case .synchronized = state { await tasks.reload() }
            }
        }
    }

    func loadConfiguration() async {
        do {
            configuration = try await configurationStore.load()
            await manager.configureSynchronization(configuration)
            state = await manager.synchronizationStatus()
        } catch { configurationError = "Could not read the saved connection: \(error.localizedDescription)" }
    }

    func saveConnection(serverURL: String, clientID: String, secret: String) async -> Bool {
        isSaving = true
        defer { isSaving = false }
        do {
            guard let identity = UUID(uuidString: clientID.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                configurationError = "Enter the client ID UUID used by your other Taskwarrior clients."
                return false
            }
            let configuration = try SyncConfiguration(serverURL: serverURL, clientID: identity, encryptionSecret: secret)
            try await configurationStore.save(configuration)
            self.configuration = configuration
            configurationError = nil
            await manager.configureSynchronization(configuration)
            await manager.requestSynchronization(trigger: .appOpened)
            state = await manager.synchronizationStatus()
            return true
        } catch { configurationError = error.localizedDescription; return false }
    }

    func disconnect() async {
        do {
            try await configurationStore.remove()
            configuration = nil
            configurationError = nil
            await manager.configureSynchronization(nil)
            state = .localOnly
        } catch { configurationError = "Could not remove the connection: \(error.localizedDescription)" }
    }

    func synchronize() async -> Bool {
        guard configuration != nil else {
            configurationError = SynchronizationError.notConfigured.localizedDescription
            return false
        }
        configurationError = nil
        do {
            _ = try await manager.synchronize(trigger: .manualRetry)
            state = await manager.synchronizationStatus()
            return true
        } catch {
            state = await manager.synchronizationStatus()
            if error is CancellationError { return false }
            if case .failed = state {} else { configurationError = error.localizedDescription }
            return false
        }
    }
}
