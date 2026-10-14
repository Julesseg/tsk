import Foundation
import Observation
import TskCore
import TskNative

@MainActor @Observable
final class TaskStore {
    let manager: TaskManager
    var tasks: [TaskRecord] = []
    var error: String?
    var isSaving = false
    var isLoading = false

    init() {
        let support = URL.applicationSupportDirectory
        let testName = ProcessInfo.processInfo.environment["TSK_TEST_REPLICA_NAME"]
        let directory = support.appendingPathComponent(testName.map { "UITests/\($0)" } ?? "TaskChampion", isDirectory: true)
        manager = TaskManager(replica: TaskChampionReplica(directory: directory))
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            tasks = try await manager.tasks()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func save(_ draft: TaskDraft) async -> Bool {
        isSaving = true
        defer { isSaving = false }
        do {
            let saved = try await manager.create(draft)
            tasks.insert(saved, at: 0)
            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}
