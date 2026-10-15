import Foundation
import Observation
import TskCore
import TskNative

@MainActor @Observable
final class TaskStore {
    let manager: TaskManager
    let directory: URL
    var tasks: [TaskRecord] = []
    var savedViews: [SavedTaskView] = []
    var attributeDefinitions: [TaskAttributeDefinition] = []
    var customView: CustomViewSelection?
    var allTasks: [TaskRecord] = []
    var query: TaskQuery = .unfinished
    var projectSelection: TaskProjectSelection = .all
    var availableProjects: [String] = []
    var error: String?
    var presentedTaskPanels: Set<UUID> = []
    var isSaving = false
    var isLoading = false
    private let fixedDate: Date?
    var currentDate: Date { fixedDate ?? Date() }
    var upcomingDays: [UpcomingDay] { UpcomingDay.groups(tasks: tasks, at: currentDate) }
    private var reloadGeneration = 0
    var nextFilterEvaluation: Date?
    var filterRefreshGeneration = 0

    init() throws {
        let testName = ProcessInfo.processInfo.environment["TSK_TEST_REPLICA_NAME"]
        directory = try TaskChampionSession.directory(testName: testName)
        let fixed = testName.flatMap { _ in ProcessInfo.processInfo.environment["TSK_TEST_NOW"] }.flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:))
        fixedDate = fixed
        manager = TaskChampionSession.makeManager(directory: directory, now: { fixed ?? Date() })
    }

    func availability(for task: TaskRecord, at date: Date) -> TaskAvailability {
        task.availability(at: fixedDate ?? date, tasks: allTasks)
    }

    func reload() async {
        reloadGeneration += 1
        let generation = reloadGeneration
        let requestedQuery = query
        let requestedProject = projectSelection
        let requestedCustom = customView
        isLoading = true
        defer { if generation == reloadGeneration { isLoading = false } }
        do {
            let snapshot: TaskViewSnapshot
            if let requestedCustom { snapshot = try await manager.viewSnapshot(filter: requestedCustom.expression) }
            else { snapshot = try await manager.viewSnapshot(query: requestedQuery, project: requestedProject) }
            guard generation == reloadGeneration, query == requestedQuery, projectSelection == requestedProject, customView == requestedCustom else { return }
            tasks = snapshot.tasks
            allTasks = snapshot.allTasks
            availableProjects = snapshot.projects
            nextFilterEvaluation = fixedDate == nil ? snapshot.nextEvaluation : nil
            filterRefreshGeneration += 1
            error = nil
        } catch {
            guard generation == reloadGeneration, query == requestedQuery, projectSelection == requestedProject, customView == requestedCustom else { return }
            self.error = error.localizedDescription
        }
    }

    func save(_ draft: TaskDraft) async -> Bool {
        await perform { try await $0.create(draft) } != nil
    }

    func update(id: UUID, changes: TaskAttributePatch) async -> TaskRecord? {
        await perform { try await $0.update(id: id, changes: changes) }
    }

    func dependencyLinks(for task: TaskRecord) -> [TaskDependencyLink] { task.dependencyLinks(in: allTasks) }

    func addDependency(id: UUID, prerequisiteID: UUID) async -> TaskRecord? {
        await perform { try await $0.addDependency(id: id, prerequisiteID: prerequisiteID) }
    }

    func removeDependency(id: UUID, reference: String) async -> TaskRecord? {
        await perform { try await $0.removeDependency(id: id, reference: reference) }
    }

    func loadAttributeDefinitions() async throws {
        let definitions = try await manager.attributeDefinitions()
        let changed = definitions != attributeDefinitions
        attributeDefinitions = definitions
        if changed, customView != nil { await reload() }
    }

    func updateUserAttributes(id: UUID, changes: TaskAttributePatch) async -> TaskRecord? {
        await perform { try await $0.updateUserAttributes(id: id, changes: changes) }
    }

    func addAnnotation(id: UUID, text: String) async -> TaskRecord? {
        await perform { try await $0.addAnnotation(id: id, text: text) }
    }

    func editAnnotation(id: UUID, reference: String, text: String) async -> TaskRecord? {
        await perform { try await $0.editAnnotation(id: id, reference: reference, text: text) }
    }

    func complete(id: UUID) async -> TaskRecord? {
        await perform { try await $0.complete(id: id) }
    }

    func perform(_ action: @Sendable (TaskManager) async throws -> TaskRecord) async -> TaskRecord? {
        guard !isSaving else { return nil }
        isSaving = true
        defer { isSaving = false }
        do {
            let saved = try await action(manager)
            allTasks.removeAll { $0.id == saved.id }
            allTasks.append(saved)
            let index = tasks.firstIndex { $0.id == saved.id } ?? 0
            tasks.removeAll { $0.id == saved.id }
            if customView == nil && query.includes(saved, now: currentDate) && projectSelection.includes(saved) { tasks.insert(saved, at: min(index, tasks.count)) }
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
