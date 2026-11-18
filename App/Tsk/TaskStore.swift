import Foundation
import Observation
import TskCore
import TskNative

@MainActor @Observable
final class TaskStore {
    let manager: TaskManager
    let directory: URL
    var tasks: [TaskRecord] = []
    var taskDrag: TaskDragSession?
    var isTaskDragLifted = false
    #if DEBUG
    var taskDragProof = ""
    #endif
    var selectedWorkspaceView: WorkspaceView = .today
    var allTasks: [TaskRecord] = []
    var query: TaskQuery = .today
    var plannerDay: Date?
    var displayedDay: Date { Calendar.autoupdatingCurrent.startOfDay(for: plannerDay ?? currentDate) }
    var isDayPage: Bool { query == .today }

    func browseDay(_ day: Date, cachedTasks: [TaskRecord]? = nil) {
        guard taskDrag == nil, selectedTaskIDs.isEmpty, !isSelectionPressActive, rowEditing == nil, !isSaving else { return }
        if !isDayPage { selectWorkspaceView(.today) }
        let nextDay = Calendar.autoupdatingCurrent.startOfDay(for: day)
        if displayedDay != nextDay { tasks = cachedTasks ?? [] }
        plannerDay = nextDay
        captureConfirmation = nil
        Task { await reload() }
    }

    func moveDay(by offset: Int) {
        guard isDayPage, !isSelectingTasks,
              let day = Calendar.autoupdatingCurrent.date(byAdding: .day, value: offset, to: displayedDay) else { return }
        browseDay(day)
    }

    var projectSelection: TaskProjectSelection = .all
    var availableProjects: [String] = []
    var error: String?
    private var taskActionPanels: Set<UUID> = []
    @ObservationIgnored private var taskActionCommit: (id: UUID, save: @MainActor () async -> Bool)?
    @ObservationIgnored private weak var taskActionSource: TaskStore?

    var presentedTaskPanels: Set<UUID> {
        get { taskActionSource?.presentedTaskPanels ?? taskActionPanels }
        set {
            if let taskActionSource { taskActionSource.presentedTaskPanels = newValue }
            else { taskActionPanels = newValue }
        }
    }

    var taskActionDraftCommit: (id: UUID, save: @MainActor () async -> Bool)? {
        get { taskActionSource?.taskActionDraftCommit ?? taskActionCommit }
        set {
            if let taskActionSource { taskActionSource.taskActionDraftCommit = newValue }
            else { taskActionCommit = newValue }
        }
    }

    struct NavigationLocation {
        let workspace: WorkspaceView
        let query: TaskQuery
        let project: TaskProjectSelection
        let plannerDay: Date?
    }
    var navigationReturn: NavigationLocation?
    var navigationTitle: String?

    func openNavigation(_ destination: TaskNavigationDestination) async throws {
        if navigationReturn == nil {
            navigationReturn = NavigationLocation(workspace: selectedWorkspaceView, query: query, project: projectSelection, plannerDay: plannerDay)
        }
        endTaskSelection()
        captureConfirmation = nil
        selectWorkspaceView(destination.view.workspace)
        query = destination.view.query
        if case .project(let name) = destination.view { projectSelection = .project(name) }
        navigationTitle = destination.title
        tasks = destination.snapshot.listTasks
        allTasks = destination.snapshot.allTasks
        availableProjects = destination.snapshot.projects
        nextFilterEvaluation = destination.snapshot.nextEvaluation
        error = nil
        if let task = destination.task {
            expandRow(task)
            guard let row = rowEditing, row.draft.original.id == task.id else {
                throw TaskActionError.navigationFailed("The task could not be expanded in its containing list.")
            }
            await row.setExpanded(true, reduceMotion: true)
        }
    }

    func returnFromNavigation() async -> Bool {
        guard await prepareForTaskActionNavigation(), let location = navigationReturn else { return false }
        selectedWorkspaceView = location.workspace
        query = location.query
        projectSelection = location.project
        plannerDay = location.plannerDay
        navigationReturn = nil
        navigationTitle = nil
        await reload()
        return true
    }

    func prepareForTaskActionNavigation() async -> Bool {
        guard !isSaving else { error = "A task is still saving. Try the URL again after it finishes."; return false }
        let allowed = taskActionDraftCommit.map { Set([$0.id]) } ?? []
        guard presentedTaskPanels.subtracting(allowed).isEmpty else {
            error = "Finish the current editing panel before opening a task URL."
            return false
        }
        if let commit = taskActionDraftCommit, !(await commit.save()) { return false }
        return await saveRowForTaskActionNavigation()
    }

    func saveRowForTaskActionNavigation() async -> Bool {
        guard !isSaving else { error = "A task is still saving. Try again after it finishes."; return false }
        if let row = rowEditing, row.isCapture, row.draft.taskDraft.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            row.error = TaskManagementError.emptyDescription.localizedDescription
            error = row.error
            return false
        }
        if let row = rowEditing, !(await row.saveAndCollapse(in: self, reduceMotion: true, includingParameter: true)) {
            error = row.error ?? error ?? "The current task is still saving or its editing panel is open."
            return false
        }
        return true
    }

    var isSaving = false
    var isLoading = false
    private let fixedDate: Date?
    var currentDate: Date { fixedDate ?? Date() }
    let completionFeedback = TaskCompletionFeedback()
    #if DEBUG
    var selectionGestureProof = ""
    #endif
    var isSelectionPressActive = false
    var taskSelectionGeneration = 0
    var isSelectingTasks: Bool { !selectedTaskIDs.isEmpty }
    var selectedTaskIDs: Set<UUID> = [] {
        didSet {
            if selectedTaskIDs.isEmpty {
                selectionChanges = TaskSelectionChanges()
                selectionDateField = nil
                error = nil
            }
        }
    }
    var selectionChanges = TaskSelectionChanges()
    var selectionDateField: TaskDateField?
    var isSelectionGestureActive = false
    var selectionGestureTasks: [TaskRecord]?
    var rowEditing: TaskRowEditing?
    var captureConfirmation: TaskRecord?
    var captureTask: TaskRecord? {
        guard let editing = rowEditing, editing.isCapture, editing.context == completionContext else { return nil }
        return editing.draft.original
    }

    func activateSelectionGesture() -> Bool {
        guard !isSaving, !isSelectionGestureActive, rowEditing == nil, taskDrag == nil, selectionDateField == nil else { return false }
        selectionGestureTasks = visibleTasks
        isSelectionGestureActive = true
        return true
    }

    func applySelectionGesture(startingAt initial: UUID, from selection: Set<UUID>, entering path: [TaskSelectionVisit]) -> Bool {
        let updated = manager.selectedTasks(in: visibleTasks, from: selection, startingAt: initial, entering: path)
        guard updated != selectedTaskIDs else { return false }
        selectedTaskIDs = updated
        return true
    }

    func endSelectionGesture() {
        isSelectionGestureActive = false
        selectionGestureTasks = nil
    }

    func endTaskSelection() {
        isSelectionPressActive = false
        taskSelectionGeneration += 1
        selectedTaskIDs = []
        selectionDateField = nil
        selectionChanges = TaskSelectionChanges()
        error = nil
        endSelectionGesture()
    }

    func scheduleSelection(on day: Date) async -> Bool {
        guard !isSaving, !isSelectionGestureActive, !isSelectionPressActive, !selectedTaskIDs.isEmpty else { return false }
        let ordered = visibleTasks.filter { selectedTaskIDs.contains($0.id) }.map(\.id)
        let remaining = selectedTaskIDs.subtracting(ordered).sorted { $0.uuidString < $1.uuidString }
        let generation = taskSelectionGeneration
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await manager.schedule(ids: ordered + remaining, change: .day(day))
            if generation == taskSelectionGeneration { endTaskSelection() }
            await reload()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func beginCapture(reduceMotion: Bool) async {
        guard !isSaving else { return }
        if let editing = rowEditing {
            guard !editing.isCapture, await editing.saveAndCollapse(in: self, reduceMotion: reduceMotion) else { return }
        }
        guard rowEditing == nil else { return }
        endTaskSelection()
        captureConfirmation = nil
        let context: TaskCaptureContext
        if isDayPage { context = .day(displayedDay) }
        else if let name = projectSelection.projectName { context = .project(name) }
        else { context = .inbox }
        let draft = TaskRowDraft(capturing: context)
        rowEditing = TaskRowEditing(capturing: draft, context: completionContext, tasks: visibleTasks, now: currentDate)
    }

    func confirmCapture(_ task: TaskRecord) {
        captureConfirmation = task
        Task {
            try? await Task.sleep(for: .seconds(3))
            if captureConfirmation?.id == task.id { captureConfirmation = nil }
        }
    }
    var completionContext: TaskCompletionFeedback.Context {
        .init(query: query, project: projectSelection, plannerDay: isDayPage ? displayedDay : nil)
    }
    var visibleTasks: [TaskRecord] {
        if let taskDrag { return taskDrag.tasks }
        if let selectionGestureTasks { return selectionGestureTasks }
        if let rowEditing, rowEditing.context == completionContext { return rowEditing.tasks }
        return completionFeedback.visibleTasks(tasks, context: completionContext)
    }
    func expandRow(_ task: TaskRecord, rowID: String? = nil) {
        guard !isSelectionPressActive, !isSelectingTasks, rowEditing == nil, !isSaving, task.canOpenInWorkspace, visibleTasks.contains(where: { $0.id == task.id }) else { return }
        rowEditing = TaskRowEditing(task: task, rowID: rowID ?? "task-" + task.id.uuidString, context: completionContext, tasks: visibleTasks, now: currentDate)
    }
    private var reloadGeneration = 0
    var nextFilterEvaluation: Date?
    var filterRefreshGeneration = 0

    func selectWorkspaceView(_ view: WorkspaceView) {
        navigationTitle = nil
        endTaskSelection()
        selectedWorkspaceView = view
        plannerDay = nil
        projectSelection = .all
        query = view.query

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

    private init(manager: TaskManager, directory: URL, fixedDate: Date?) {
        self.manager = manager
        self.directory = directory
        self.fixedDate = fixedDate
        query = .all
    }

    func linkedTaskStore() -> TaskStore {
        let store = TaskStore(manager: manager, directory: directory, fixedDate: fixedDate)
        store.taskActionSource = taskActionSource ?? self
        return store
    }

    func observeParticipantChanges() async {
        do {
            var prior: TaskChangeVersion?
            for try await version in await manager.changeUpdates() {
                if Task.isCancelled { return }
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
        task.availability(at: fixedDate ?? date)
    }

    func reload() async {
        reloadGeneration += 1
        let generation = reloadGeneration
        let requestedQuery = query
        let requestedDay = isDayPage ? displayedDay : nil
        let requestedProject = projectSelection
        isLoading = true
        defer { if generation == reloadGeneration { isLoading = false } }
        do {
            let snapshot: TaskViewSnapshot
            if let requestedDay { snapshot = try await manager.dayPageSnapshot(on: requestedDay) }
            else { snapshot = try await manager.viewSnapshot(query: requestedQuery, project: requestedProject) }
            guard generation == reloadGeneration, query == requestedQuery, projectSelection == requestedProject, (isDayPage ? displayedDay : nil) == requestedDay else { return }
            tasks = snapshot.listTasks
            allTasks = snapshot.allTasks
            availableProjects = snapshot.projects
            nextFilterEvaluation = fixedDate == nil ? snapshot.nextEvaluation : nil
            filterRefreshGeneration += 1
            error = nil
        } catch {
            guard generation == reloadGeneration, query == requestedQuery, projectSelection == requestedProject, (isDayPage ? displayedDay : nil) == requestedDay else { return }
            self.error = error.localizedDescription
        }
    }

    func save(_ draft: TaskDraft) async -> Bool {
        await perform { try await $0.create(draft) } != nil
    }

    func update(id: UUID, changes: TaskAttributePatch) async -> TaskRecord? {
        await perform { try await $0.update(id: id, changes: changes) }
    }

    func updateRow(_ draft: TaskRowDraft) async -> TaskRecord? {
        await perform { try await $0.updateRow(draft) }
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

    func reopen(id: UUID) async -> TaskRecord? {
        await perform { try await $0.reopen(id: id) }
    }

    func completeFromList(id: UUID, animated: Bool = true) async -> TaskRecord? {
        guard !isSelectionPressActive, !isSaving, let task = visibleTasks.first(where: { $0.id == id }), task.canComplete else { return nil }
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
            if query.includes(saved, now: currentDate) && projectSelection.includes(saved) { tasks.insert(saved, at: min(index, tasks.count)) }
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

extension TaskStore {
    var taskDragContext: TaskDragContext? {
        if isDayPage { return .day(displayedDay) }
        if case .project(let name) = projectSelection, query == .unfinished { return .project(name) }
        return nil
    }

    var canDragTasks: Bool { taskDragContext != nil && taskDrag == nil && (!isSelectingTasks || !selectedTaskIDs.isEmpty) && !isSelectionGestureActive && !isSelectionPressActive && selectionDateField == nil && !isSaving && rowEditing == nil }

    func beginTaskDrag(id: UUID) -> Bool {
        guard canDragTasks, let context = taskDragContext, !isSelectingTasks || selectedTaskIDs.contains(id) else { return false }
        do {
            taskDrag = try TaskDragSession(tasks: visibleTasks, ids: isSelectingTasks ? Array(selectedTaskIDs) : [id], context: context)
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func finishTaskDrop() async {
        guard let drag = taskDrag, !isSaving else { return }
        isSaving = true
        defer { isTaskDragLifted = false; taskDrag = nil; isSaving = false }
        do {
            _ = try await manager.drop(drag)
            error = nil
            await reload()
        } catch { self.error = error.localizedDescription }
    }
}
