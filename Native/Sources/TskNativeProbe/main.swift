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
        if arguments.count == 3, arguments[1] == "read-tasks" {
            do {
                let records = try await TaskChampionReplica(directory: URL(fileURLWithPath: arguments[2])).readExistingTasks()
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                print(String(decoding: try encoder.encode(records.sorted { $0.id.uuidString < $1.id.uuidString }), as: UTF8.self))
            } catch {
                FileHandle.standardError.write(Data("Native storage readback failed: \(error.localizedDescription)\n".utf8))
                exit(EXIT_FAILURE)
            }
            return
        }
        if arguments.count == 5, arguments[1] == "participant-change" {
            do {
                let manager = try await TaskChampionSession.open(directory: URL(fileURLWithPath: arguments[2]))
                let saved = try await manager.complete(id: UUID(uuidString: arguments[3])!)
                let view = try await manager.saveView(name: "Other process completed", expression: "status:completed")
                try write(["saved": saved.id.uuidString, "view": view.id.uuidString], to: arguments[4])
            } catch { try? write(["error": error.localizedDescription], to: arguments[4]) }
            return
        }
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
        fatalError("Unknown native probe command")
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
