import Foundation
import Observation
import TskCore
import TskNative

@MainActor @Observable
final class TaskStore {
    let manager: TaskManager
    let directory: URL
    var tasks: [TaskRecord] = []
    var query: TaskQuery = .unfinished
    var projectSelection: TaskProjectSelection = .all
    var availableProjects: [String] = []
    var error: String?
    var isSaving = false
    var isLoading = false
    private let fixedDate: Date?
    var currentDate: Date { fixedDate ?? Date() }
    var upcomingDays: [UpcomingDay] { UpcomingDay.groups(tasks: tasks, at: currentDate) }
    private var reloadGeneration = 0

    init() {
        let testName = ProcessInfo.processInfo.environment["TSK_TEST_REPLICA_NAME"]
        directory = TaskChampionSession.directory(testName: testName)
        let fixed = testName.flatMap { _ in ProcessInfo.processInfo.environment["TSK_TEST_NOW"] }.flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:))
        fixedDate = fixed
        manager = TaskManager(replica: TaskChampionReplica(directory: directory), now: { fixed ?? Date() })
    }

    func availability(for task: TaskRecord, at date: Date) -> TaskAvailability {
        task.availability(at: fixedDate ?? date)
    }

    func reload() async {
        reloadGeneration += 1
        let generation = reloadGeneration
        let requestedQuery = query
        let requestedProject = projectSelection
        isLoading = true
        defer { if generation == reloadGeneration { isLoading = false } }
        do {
            let loaded = try await manager.tasks(query: requestedQuery, project: requestedProject)
            let projects = try await manager.projects()
            guard generation == reloadGeneration, query == requestedQuery, projectSelection == requestedProject else { return }
            tasks = loaded
            availableProjects = projects
            error = nil
        } catch {
            guard generation == reloadGeneration, query == requestedQuery, projectSelection == requestedProject else { return }
            self.error = error.localizedDescription
        }
    }

    func save(_ draft: TaskDraft) async -> Bool {
        await perform { try await $0.create(draft) } != nil
    }

    func update(id: UUID, changes: TaskAttributePatch) async -> TaskRecord? {
        await perform { try await $0.update(id: id, changes: changes) }
    }

    func complete(id: UUID) async -> TaskRecord? {
        await perform { try await $0.complete(id: id) }
    }

    private func perform(_ action: @Sendable (TaskManager) async throws -> TaskRecord) async -> TaskRecord? {
        guard !isSaving else { return nil }
        isSaving = true
        defer { isSaving = false }
        do {
            let saved = try await action(manager)
            let index = tasks.firstIndex { $0.id == saved.id } ?? 0
            tasks.removeAll { $0.id == saved.id }
            if query.includes(saved, now: currentDate) && projectSelection.includes(saved) { tasks.insert(saved, at: min(index, tasks.count)) }
            if !saved.project.isEmpty, !availableProjects.contains(where: { UTF8String($0) == UTF8String(saved.project) }) {
                availableProjects.append(saved.project)
                availableProjects.sort { UTF8String($0) < UTF8String($1) }
            }
            error = nil
            await reload()
            return saved
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }
}
