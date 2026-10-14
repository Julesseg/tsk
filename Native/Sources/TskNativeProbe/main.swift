import Foundation
import TskCore
import TskNative

@main
struct MutationProbe {
    static func main() async {
        let arguments = CommandLine.arguments
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
