import Foundation
import TskCore
import TskNative
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@main
struct MutationProbe {
    static func main() async {
        let arguments = CommandLine.arguments
        if arguments.count == 7, arguments[1] == "complete-occurrence" {
            do {
                try Data().write(to: URL(fileURLWithPath: arguments[4]))
                while !FileManager.default.fileExists(atPath: arguments[5]) { try await Task.sleep(nanoseconds: 10_000_000) }
                let manager = try await TaskChampionSession.open(directory: URL(fileURLWithPath: arguments[2]))
                let saved = try await manager.complete(id: UUID(uuidString: arguments[3])!)
                try write(["saved": saved.id.uuidString], to: arguments[6])
            } catch { try? write(["error": error.localizedDescription], to: arguments[6]) }
            return
        }
        if arguments.count == 7, arguments[1] == "save-attribute" {
            do {
                let directory = URL(fileURLWithPath: arguments[2])
                let store = AttributeBarrierStore(directory: directory, ready: URL(fileURLWithPath: arguments[4]), release: URL(fileURLWithPath: arguments[5]))
                let manager = TaskManager(replica: TaskChampionReplica(directory: directory), attributeDefinitions: store)
                let saved = try await manager.saveAttributeDefinition(name: arguments[3], type: .string)
                try write(["saved": saved.name.rawValue], to: arguments[6])
            } catch { try? write(["error": error.localizedDescription], to: arguments[6]) }
            return
        }
        if arguments.count == 7, arguments[1] == "save-view" {
            do {
                let directory = URL(fileURLWithPath: arguments[2])
                let store = SavedViewBarrierStore(directory: directory, ready: URL(fileURLWithPath: arguments[4]), release: URL(fileURLWithPath: arguments[5]))
                let manager = TaskManager(replica: TaskChampionReplica(directory: directory), viewDefinitions: store)
                let saved = try await manager.saveView(name: arguments[3], expression: "project:Work")
                try write(["saved": saved.id.uuidString], to: arguments[6])
            } catch { try? write(["error": error.localizedDescription], to: arguments[6]) }
            return
        }
        if arguments.dropFirst().first == "verify-ui-sync" {
            do { try await verifyUISynchronization(); return }
            catch { print("Real UI synchronization verification failed: \(error)"); exit(EXIT_FAILURE) }
        }
        guard arguments.count == 8 else { fatalError("Expected replica, source, prerequisite, ready, release, output, coordination") }
        do {
            let replica = BarrierReplica(directory: URL(fileURLWithPath: arguments[1]), ready: URL(fileURLWithPath: arguments[4]), release: URL(fileURLWithPath: arguments[5]), coordinated: arguments[7] == "coordinated")
            let manager = TaskManager(replica: replica)
            let record = try await manager.addDependency(id: UUID(uuidString: arguments[2])!, prerequisiteID: UUID(uuidString: arguments[3])!)
            try write(["saved": record.id.uuidString], to: arguments[6])
        } catch {
            try? write(["error": error.localizedDescription], to: arguments[6])
        }
    }

    static func verifyUISynchronization() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let url = environment["TSK_UI_SYNC_SERVER_URL"], let rawClient = environment["TSK_UI_SYNC_CLIENT_ID"], let client = UUID(uuidString: rawClient), let secret = environment["TSK_UI_SYNC_SECRET"], let token = environment["TSK_UI_SYNC_FIXTURE_TOKEN"], let directory = environment["TSK_UI_SYNC_PEER_DIRECTORY"], let proof = environment["TSK_UI_SYNC_PEER_PROOF"] else { throw TaskManagementError.storage("Missing isolated UI peer settings") }
        let manager = TaskManager(replica: TaskChampionReplica(directory: URL(fileURLWithPath: directory)))
        let configuration = try SyncConfiguration(serverURL: url, clientID: client, encryptionSecret: secret)
        let records = try await manager.synchronize(using: configuration)
        let matching = records.filter { $0.description == "Hosted task " + token }
        guard matching.count == 1, matching[0].status == "pending" else { throw TaskManagementError.storage("The independent encrypted peer did not find the task saved through UI") }
        try write(["id": matching[0].id.uuidString, "description": matching[0].description, "status": matching[0].status, "clientID": rawClient, "token": token], to: proof)
    }

    static func write(_ value: [String: String], to path: String) throws {
        try JSONSerialization.data(withJSONObject: value).write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}

private actor BarrierReplica: TaskMutationCoordinatingReplica {
    let native: TaskChampionReplica
    let ready: URL
    let release: URL
    let coordinated: Bool
    var didRead = false

    init(directory: URL, ready: URL, release: URL, coordinated: Bool) {
        native = TaskChampionReplica(directory: directory)
        self.ready = ready
        self.release = release
        self.coordinated = coordinated
    }

    func acquireMutationLease() async throws -> any TaskMutationLease {
        if coordinated { return try await native.acquireMutationLease() }
        return UncoordinatedLease()
    }

    func tasks() async throws -> [TaskRecord] {
        let records = try await native.tasks()
        if !didRead {
            didRead = true
            try Data().write(to: ready)
            while !FileManager.default.fileExists(atPath: release.path) { try await Task.sleep(nanoseconds: 10_000_000) }
        }
        return records
    }

    func create(id: UUID, attributes: TaskAttributes) async throws -> TaskRecord { try await native.create(id: id, attributes: attributes) }
    func update(id: UUID, changes: TaskAttributePatch) async throws -> TaskRecord { try await native.update(id: id, changes: changes) }
}

private struct UncoordinatedLease: TaskMutationLease {
    func release() {}
}

private actor SavedViewBarrierStore: TaskViewDefinitionsStore {
    let native: LocalTaskViewStore
    let ready: URL
    let release: URL

    init(directory: URL, ready: URL, release: URL) {
        native = LocalTaskViewStore(directory: directory)
        self.ready = ready
        self.release = release
    }

    func load() async throws -> [SavedTaskView] {
        let definitions = try await native.load()
        try Data().write(to: ready)
        let deadline = Date().addingTimeInterval(10)
        while !FileManager.default.fileExists(atPath: release.path) {
            guard Date() < deadline else { throw TaskManagementError.storage("Saved-view probe timed out") }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        return definitions
    }

    func save(_ definitions: [SavedTaskView]) async throws { try await native.save(definitions) }
}

private actor AttributeBarrierStore: TaskAttributeDefinitionsStore {
    let native: LocalTaskAttributeStore
    let ready: URL
    let release: URL

    init(directory: URL, ready: URL, release: URL) {
        native = LocalTaskAttributeStore(directory: directory)
        self.ready = ready
        self.release = release
    }

    func load() async throws -> [TaskAttributeDefinition] {
        let definitions = try await native.load()
        try Data().write(to: ready)
        let deadline = Date().addingTimeInterval(10)
        while !FileManager.default.fileExists(atPath: release.path) {
            guard Date() < deadline else { throw TaskManagementError.storage("Attribute-definition probe timed out") }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        return definitions
    }

    func save(_ definitions: [TaskAttributeDefinition]) async throws { try await native.save(definitions) }
}
