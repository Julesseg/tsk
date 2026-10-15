import SwiftUI
import TskCore
import EventKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var store: TaskStore
    @State private var synchronization: SynchronizationStore
    @State private var opportunities: SynchronizationOpportunities
    @State private var continuousReminders: ContinuousReminderController
    @State private var isConfiguringContinuousReminders = false
    @State private var isCapturing = false
    @State private var isConfiguringSync = false
    @State private var isChoosingCustomView = false
    @State private var isShowingShortcuts = false
    @State private var isShowingRecurring = false
    @State private var isDefiningAttributes = false
    @State private var isImportingReminders = false
    @State private var editingTask: TaskRecord?
    @State private var selectedTaskID: UUID?
    @State private var path: [UUID] = []
    @State private var sidebarError: String?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    init(store: TaskStore) {
        _store = State(initialValue: store)
        _synchronization = State(initialValue: SynchronizationStore(manager: store.manager, directory: store.directory))
        _opportunities = State(initialValue: SynchronizationOpportunities(manager: store.manager))
        _continuousReminders = State(initialValue: ContinuousReminderController(store: store))
    }

    var body: some View {
        Group {
            if sizeClass == .regular {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    TaskWorkspaceSidebar(store: store, openView: openView, openProject: openProject, customViews: { isChoosingCustomView = true }, synchronization: { isConfiguringSync = true }, shortcuts: { isShowingShortcuts = true }, recurring: { isShowingRecurring = true }, attributeDefinitions: { isDefiningAttributes = true }, reminders: { isImportingReminders = true }, continuousReminders: { isConfiguringContinuousReminders = true })
                        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
                } content: {
                    taskList(selection: $selectedTaskID)
                        .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 440)
                } detail: {
                    if let task = selectedTask {
                        TaskDetailView(store: store, task: task, edit: { editingTask = $0 })
                            .id(task.id)
                    } else {
                        ContentUnavailableView("Select a task", systemImage: "sidebar.right", description: Text("Choose a task to review its details, edit it, or mark it complete."))
                            .accessibilityIdentifier("workspace-detail-empty")
                    }
                }
                .navigationSplitViewStyle(.balanced)
                .accessibilityIdentifier("task-workspace")
            } else {
                NavigationStack(path: $path) {
                    taskList(selection: nil)
                        .safeAreaInset(edge: .top) { compactViewPicker }
                        .navigationDestination(for: UUID.self) { id in
                            if let task = store.allTasks.first(where: { $0.id == id }) {
                                TaskDetailView(store: store, task: task, edit: { editingTask = $0 })
                            } else {
                                ContentUnavailableView("Task unavailable", systemImage: "questionmark.folder")
                            }
                        }
                }
            }
        }
        .focusedSceneValue(\.taskWorkspace, workspaceActions)
        .sheet(isPresented: $isConfiguringContinuousReminders) { ContinuousReminderSettingsView(controller: continuousReminders) }
        .sheet(isPresented: $isImportingReminders) { ReminderImportView(store: store) }
        .sheet(isPresented: $isDefiningAttributes) { TaskAttributeDefinitionsView(store: store) }
        .sheet(isPresented: $isCapturing) { TaskEditorView(store: store) }
        .sheet(isPresented: $isChoosingCustomView, onDismiss: { Task { await loadSavedViews() } }) { CustomViewsView(store: store) }
        .sheet(isPresented: $isConfiguringSync) { SyncSettingsView(synchronization: synchronization, tasks: store) }
        .sheet(isPresented: $isShowingRecurring) { RecurringTemplatesView(store: store) }
        .sheet(isPresented: $isShowingShortcuts) { NavigationStack { TaskShortcutsView().toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { isShowingShortcuts = false } } } } }
        .sheet(item: $editingTask) { task in TaskEditorView(store: store, task: task) }
        .task(id: TaskListSelection(query: store.query, project: store.projectSelection, customView: store.customView)) {
            selectedTaskID = nil
            path = []
            await store.reload()
        }
        .task(id: scenePhase == .active ? store.filterRefreshGeneration : nil) {
            guard scenePhase == .active, let next = store.nextFilterEvaluation else { return }
            do {
                try await Task.sleep(for: .seconds(max(0.05, next.timeIntervalSinceNow)))
                await store.reload()
            } catch {}
        }
        .task {
            synchronization.startObserving(tasks: store)
            await synchronization.loadConfiguration()
            await loadSavedViews()
            opportunities.start()
            await opportunities.foreground()
            await continuousReminders.scan()
        }
        .onChange(of: path) { _, newPath in if sizeClass != .regular { selectedTaskID = newPath.last } }
        .onChange(of: sizeClass) { _, size in
            path = size == .regular ? [] : selectedTaskID.map { [$0] } ?? []
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await synchronization.loadConfiguration()
                    await opportunities.foreground()
                    await continuousReminders.scan()
                    await store.reload()
                    await loadSavedViews()
                }
            } else if phase == .background { opportunities.background() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in continuousReminders.sourceChanged() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in Task { await store.reload() } }
    }

    private func taskList(selection: Binding<UUID?>?) -> some View {
        TaskListView(store: store, selection: selection, edit: { editingTask = $0 })
            .navigationTitle(store.customView?.name ?? "Tasks")
            .toolbar {
                if sizeClass != .regular {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        Button("Recurring templates", systemImage: "repeat") { isShowingRecurring = true }.accessibilityIdentifier("recurring-templates")
                        Button("Shortcuts and Siri", systemImage: "square.stack.3d.up") { isShowingShortcuts = true }.accessibilityIdentifier("task-shortcuts")
                        Button("Synchronization", systemImage: "arrow.triangle.2.circlepath") { isConfiguringSync = true }.accessibilityIdentifier("synchronization-settings")
                        Button("Custom views", systemImage: "line.3.horizontal.decrease") { isChoosingCustomView = true }.accessibilityIdentifier("custom-views")
                    }
                }
                if sizeClass != .regular {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu("More", systemImage: "ellipsis") {
                            Button("Move from Reminders automatically") { isConfiguringContinuousReminders = true }.accessibilityIdentifier("continuous-reminders-settings")
                            Button("Copy from Reminders") { isImportingReminders = true }.accessibilityIdentifier("reminders-import")
                            Button("Attribute definitions") { isDefiningAttributes = true }.accessibilityIdentifier("attribute-definitions")
                        }.accessibilityIdentifier("workspace-more")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("New task", systemImage: "plus", action: capture).accessibilityIdentifier("new-task")
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    if continuousReminders.status?.active == true && (continuousReminders.status?.paused == true || continuousReminders.error != nil) {
                        Button("Reminders import needs attention") { isConfiguringContinuousReminders = true }.font(.footnote).padding().accessibilityIdentifier("continuous-reminders-attention")
                    }
                    SynchronizationStatusView(synchronization: synchronization, backgroundError: opportunities.backgroundError)
                    if let error = store.error, !store.tasks.isEmpty { errorBanner(error, retry: { Task { await store.reload() } }) }
                    if let sidebarError { errorBanner(sidebarError, retry: { Task { await loadSavedViews() } }) }
                }
            }
    }

    private var compactViewPicker: some View {
        VStack(spacing: 8) {
            if let view = store.customView {
                Button { isChoosingCustomView = true } label: { Label(view.name, systemImage: "line.3.horizontal.decrease") }.accessibilityIdentifier("active-custom-view")
                Button("Predefined views") { store.customView = nil }
            } else {
                ProjectPicker(store: store)
                Picker("Task status", selection: $store.query) {
                    Text("Today").tag(TaskQuery.today)
                    Text("Upcoming").tag(TaskQuery.upcoming)
                    Text("Unfinished").tag(TaskQuery.unfinished)
                    Text("Completed").tag(TaskQuery.completed)
                }
                .pickerStyle(.segmented).padding(.horizontal).padding(.bottom, 8)
                .accessibilityIdentifier("task-status-view")
            }
        }
    }

    private func errorBanner(_ error: String, retry: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(error).font(.footnote)
            Button("Retry", action: retry)
        }
        .padding().frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial)
    }

    private var selectedTask: TaskRecord? { store.allTasks.first { $0.id == selectedTaskID } }
    private var navigationRows: [TaskRecord] {
        store.customView == nil && store.query == .upcoming ? store.upcomingDays.flatMap(\.entries).map(\.task) : store.tasks
    }

    private var workspaceActions: TaskWorkspaceActions? {
        guard !isCapturing, !isConfiguringSync, !isChoosingCustomView, !isShowingShortcuts, !isShowingRecurring, !isDefiningAttributes, !isImportingReminders, !isConfiguringContinuousReminders, editingTask == nil, store.presentedTaskPanels.isEmpty, !store.isSaving else { return nil }
        return TaskWorkspaceActions(
            capture: capture,
            edit: selectedTask.flatMap { task in task.canEdit ? { editingTask = task } : nil },
            complete: selectedTask.flatMap { task in task.canComplete ? { Task { _ = await store.complete(id: task.id) } } : nil },
            move: moveSelection,
            reveal: selectedTask.map { task in { if sizeClass != .regular { path = [task.id] } } },
            openView: openView,
            refresh: { Task { await store.reload() } }
        )
    }

    private func capture() {
        if store.customView == nil { store.query = .unfinished }
        isCapturing = true
    }

    private func openView(_ query: TaskQuery) {
        store.customView = nil
        store.query = query
    }

    private func openProject(_ project: TaskProjectSelection) {
        store.customView = nil
        store.projectSelection = project
    }

    private func moveSelection(_ movement: TaskSelectionMovement) {
        selectedTaskID = store.manager.selectedTask(in: navigationRows, from: selectedTaskID, moving: movement)
        if sizeClass != .regular, !path.isEmpty { path = selectedTaskID.map { [$0] } ?? [] }
    }

    private func loadSavedViews() async {
        do { try await store.loadSavedViews(); sidebarError = nil }
        catch { sidebarError = error.localizedDescription }
    }
}

private struct TaskListSelection: Equatable {
    let query: TaskQuery
    let project: TaskProjectSelection
    let customView: CustomViewSelection?
}
