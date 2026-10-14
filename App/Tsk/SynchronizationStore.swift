import Foundation
import Observation
import TskCore
import TskNative

@MainActor @Observable
final class SynchronizationStore {
    private let manager: TaskManager
    private let configurationStore: SyncConfigurationStore
    var configuration: SyncConfiguration?
    var isSyncing = false
    var isSaving = false
    var error: String?
    var lastSynchronized: Date?

    init(manager: TaskManager, directory: URL) {
        self.manager = manager
        configurationStore = SyncConfigurationStore(directory: directory)
    }

    var status: String {
        if isSyncing { return "Synchronizing…" }
        if error != nil { return "Synchronization needs attention" }
        if lastSynchronized != nil { return "Synchronized with server" }
        return configuration == nil ? "Local tasks only" : "Ready to synchronize"
    }

    func loadConfiguration() async {
        do { configuration = try await configurationStore.load() }
        catch { self.error = "Could not read the saved connection: \(error.localizedDescription)" }
    }

    func saveConnection(serverURL: String, clientID: String, secret: String) async -> Bool {
        isSaving = true
        defer { isSaving = false }
        do {
            guard let identity = UUID(uuidString: clientID.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                error = "Enter the client ID UUID used by your other Taskwarrior clients."
                return false
            }
            let configuration = try SyncConfiguration(serverURL: serverURL, clientID: identity, encryptionSecret: secret)
            try await configurationStore.save(configuration)
            self.configuration = configuration
            lastSynchronized = nil
            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func disconnect() async {
        do {
            try await configurationStore.remove()
            configuration = nil
            lastSynchronized = nil
            error = nil
        } catch { self.error = "Could not remove the connection: \(error.localizedDescription)" }
    }

    func synchronize() async -> Bool {
        guard !isSyncing else { return false }
        guard let configuration else {
            error = SynchronizationError.notConfigured.localizedDescription
            return false
        }
        isSyncing = true
        error = nil
        defer { isSyncing = false }
        do {
            _ = try await manager.synchronize(using: configuration)
            lastSynchronized = Date()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}
