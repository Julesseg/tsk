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
    var workspaceViews = WorkspaceViews(customIDs: [])
    var selectedWorkspaceView: WorkspaceView = .unfinished
    private(set) var workspaceViewsLoaded = false
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
    let completionFeedback = TaskCompletionFeedback()
    #if DEBUG
    var selectionGestureProof = ""
    #endif
    var isSelectionSwipeActive = false
    var selectionSwipe: TaskSelectionSwipe?
    var taskSelectionGeneration = 0
    var isSelectingTasks = false
    var selectedTaskIDs: Set<UUID> = []
    var isSelectionGestureActive = false
    var selectionGestureTasks: [TaskRecord]?
    var selectionGestureDays: [UpcomingDay]?
    var rowEditing: TaskRowEditing?
    var completionContext: TaskCompletionFeedback.Context {
        .init(query: query, project: projectSelection, customViewID: customView?.id, filter: customView.map { UTF8String($0.expression) })
    }
    var visibleTasks: [TaskRecord] {
        if let selectionGestureTasks { return selectionGestureTasks }
        if let rowEditing, rowEditing.context == completionContext { return rowEditing.tasks }
        return completionFeedback.visibleTasks(tasks, context: completionContext)
    }
    var upcomingDays: [UpcomingDay] {
        if let selectionGestureDays { return selectionGestureDays }
        if let rowEditing, rowEditing.context == completionContext { return rowEditing.upcomingDays }
        return UpcomingDay.groups(tasks: visibleTasks, at: currentDate)
    }

    func expandRow(_ task: TaskRecord, rowID: String? = nil) {
        guard !isSelectionSwipeActive, !isSelectingTasks, rowEditing == nil, !isSaving, task.canEdit, visibleTasks.contains(where: { $0.id == task.id }) else { return }
        let upcomingID = customView == nil && query == .upcoming ? upcomingDays.flatMap(\.entries).first { $0.task.id == task.id }?.rowIdentifier : nil
        guard customView != nil || query != .upcoming || upcomingID != nil else { return }
        rowEditing = TaskRowEditing(task: task, rowID: rowID ?? upcomingID ?? "task-" + task.id.uuidString, context: completionContext, tasks: visibleTasks, now: currentDate)
    }
    private var reloadGeneration = 0
    var nextFilterEvaluation: Date?
    var filterRefreshGeneration = 0

    func loadWorkspaceViews() throws {
        if workspaceViewsLoaded {
            workspaceViews.reconcile(customIDs: savedViews.map(\.id))
        } else {
            workspaceViews = try LocalWorkspaceViewStore(directory: directory).load(customIDs: savedViews.map(\.id))
        }
        if !workspaceViewsLoaded || !workspaceViews.active.contains(selectedWorkspaceView) {
            selectWorkspaceView(workspaceViews.active[0])
        }
        workspaceViewsLoaded = true
    }

    func updateWorkspaceViews(_ change: (inout WorkspaceViews) throws -> Void) throws {
        var updated = workspaceViews
        try change(&updated)
        try LocalWorkspaceViewStore(directory: directory).save(updated)
        workspaceViews = updated
        if !updated.active.contains(selectedWorkspaceView) { selectWorkspaceView(updated.active[0]) }
    }

    func selectWorkspaceView(_ view: WorkspaceView) {
        endTaskSelection()
        selectedWorkspaceView = view
        projectSelection = .all
        customView = nil
        if let query = view.query { self.query = query }
        else if case .custom(let id) = view, let saved = savedViews.first(where: { $0.id == id }) { openView(saved) }
        else { query = .unfinished }
    }

    init() throws {
        let testName = ProcessInfo.processInfo.environment["TSK_TEST_REPLICA_NAME"]
        directory = try TaskChampionSession.directory(testName: testName)
        let fixed = testName.flatMap { _ in ProcessInfo.processInfo.environment["TSK_TEST_NOW"] }.flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:))
        fixedDate = fixed
        manager = TaskChampionSession.makeManager(directory: directory, now: { fixed ?? Date() })
    }

    init(manager: TaskManager, directory: URL) {
        self.manager = manager
        self.directory = directory
        fixedDate = nil
    }

    func observeParticipantChanges() async {
        do {
            var prior: TaskChangeVersion?
            for try await version in await manager.changeUpdates() {
                if Task.isCancelled { return }
                try await loadSavedViews()
                if let selection = customView, let id = selection.id {
                    guard let current = savedViews.first(where: { $0.id == id }) else {
                        tasks = []
                        error = TaskViewError.missingView(id).localizedDescription
                        prior = version
                        continue
                    }
                    openView(current)
                }
                try await loadAttributeDefinitions()
                await reload()
                if let prior, prior.tasks != version.tasks, version.taskOrigin == .local { await manager.requestSynchronization(trigger: .backgroundOpportunity) }
                prior = version
            }
        } catch {
            await reload()
            self.error = "Participant refresh failed: " + error.localizedDescription
        }
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
            if let requestedCustom {
                if let id = requestedCustom.id { snapshot = try await manager.viewSnapshot(reference: .custom(id)) }
                else { snapshot = try await manager.viewSnapshot(filter: requestedCustom.expression) }
            }
            else { snapshot = try await manager.viewSnapshot(query: requestedQuery, project: requestedProject) }
            guard generation == reloadGeneration, query == requestedQuery, projectSelection == requestedProject, customView == requestedCustom else { return }
            tasks = snapshot.listTasks
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

    func start(id: UUID) async -> TaskRecord? { await perform { try await $0.start(id: id) } }

    func stop(id: UUID) async -> TaskRecord? { await perform { try await $0.stop(id: id) } }

    func complete(id: UUID) async -> TaskRecord? {
        await perform { try await $0.complete(id: id) }
    }

    func completeFromList(id: UUID, animated: Bool = true) async -> TaskRecord? {
        guard !isSelectionSwipeActive, !isSaving, let task = visibleTasks.first(where: { $0.id == id }), task.canComplete else { return nil }
        let context = completionContext
        return await completionFeedback.complete(task: task, visibleTasks: visibleTasks, context: context, animated: animated,
            shouldRemove: { self.completionContext == context && !self.tasks.contains { $0.id == id } },
            operation: { await self.complete(id: id) })
    }

    func perform(_ action: @Sendable (TaskManager) async throws -> TaskRecord) async -> TaskRecord? {
        guard !isSaving else { return nil }
        isSaving = true
        defer { isSaving = false }
        let actionTrace = TaskParticipantDiagnostics.begin("taskstore.mutation")
        defer { TaskParticipantDiagnostics.end("taskstore.mutation", id: actionTrace) }
        do {
            let managerTrace = TaskParticipantDiagnostics.begin("taskstore.manager-action")
            let saved: TaskRecord
            do {
                defer { TaskParticipantDiagnostics.end("taskstore.manager-action", id: managerTrace) }
                saved = try await action(manager)
            }
            let refreshTrace = TaskParticipantDiagnostics.begin("taskstore.refresh-after-mutation")
            defer { TaskParticipantDiagnostics.end("taskstore.refresh-after-mutation", id: refreshTrace) }
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
            let reloadTrace = TaskParticipantDiagnostics.begin("taskstore.reload-after-mutation")
            await reload()
            TaskParticipantDiagnostics.end("taskstore.reload-after-mutation", id: reloadTrace)
            return saved
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }
}
