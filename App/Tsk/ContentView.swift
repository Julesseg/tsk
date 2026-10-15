import SwiftUI
import TskCore
import EventKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var store: TaskStore
    @State private var synchronization: SynchronizationStore
    @State private var opportunities: SynchronizationOpportunities
    @State private var spotlight: SpotlightController
    @State private var isShowingSpotlight = false
    @State private var calendar: TodayCalendarController
    @State private var notifications: TaskNotificationController
    @State private var isConfiguringNotifications = false
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
        _spotlight = State(initialValue: SpotlightController(store: store))
        _calendar = State(initialValue: TodayCalendarController(manager: store.manager))
        _synchronization = State(initialValue: SynchronizationStore(manager: store.manager, directory: store.directory))
        _opportunities = State(initialValue: SynchronizationOpportunities(manager: store.manager))
        _notifications = State(initialValue: TaskNotificationController(store: store))
        _continuousReminders = State(initialValue: ContinuousReminderController(store: store))
    }

    var body: some View { calendarWorkspace }

    private var navigationWorkspace: some View {
        Group {
            if sizeClass == .regular { regularWorkspace }
            else { compactWorkspace }
        }
    }

    private var regularWorkspace: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            workspaceSidebar
        } content: {
            taskList(selection: $selectedTaskID)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 440)
        } detail: {
            selectedTaskDetail
        }
        .navigationSplitViewStyle(.balanced)
        .accessibilityIdentifier("task-workspace")
    }

    @ViewBuilder private var selectedTaskDetail: some View {
        if let task = selectedTask {
            TaskDetailView(store: store, task: task, edit: { editingTask = $0 })
                .id(task.id)
        } else {
            ContentUnavailableView("Select a task", systemImage: "sidebar.right", description: Text("Choose a task to review its details, edit it, or mark it complete."))
                .accessibilityIdentifier("workspace-detail-empty")
        }
    }

    private var workspaceSidebar: some View {
        TaskWorkspaceSidebar(store: store, openView: openView, openProject: openProject, customViews: { isChoosingCustomView = true }, synchronization: { isConfiguringSync = true }, shortcuts: { isShowingShortcuts = true }, recurring: { isShowingRecurring = true }, attributeDefinitions: { isDefiningAttributes = true }, reminders: { isImportingReminders = true }, continuousReminders: { isConfiguringContinuousReminders = true }, notifications: { isConfiguringNotifications = true }, spotlight: { isShowingSpotlight = true })
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
    }

    private var compactWorkspace: some View {
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

    private var integrationSheets: some View {
        navigationWorkspace
        .taskKeyboardCommands(workspaceActions?.keyboardCommands ?? TaskKeyboardCommand.suspended)
        .sheet(isPresented: $isShowingSpotlight) { SpotlightStatusView(controller: spotlight) }
        .sheet(isPresented: $isConfiguringNotifications) { TaskNotificationSettingsView(controller: notifications) }
        .sheet(isPresented: $isConfiguringContinuousReminders) { ContinuousReminderSettingsView(controller: continuousReminders) }
        .sheet(isPresented: $isImportingReminders) { ReminderImportView(store: store) }
        .sheet(isPresented: $isDefiningAttributes) { TaskAttributeDefinitionsView(store: store) }
    }

    private var editorSheets: some View {
        integrationSheets
        .sheet(isPresented: $isCapturing) { TaskEditorView(store: store) }
        .sheet(isPresented: $isChoosingCustomView, onDismiss: { Task { await loadSavedViews() } }) { CustomViewsView(store: store) }
        .sheet(isPresented: $isConfiguringSync) { SyncSettingsView(synchronization: synchronization, tasks: store) }
        .sheet(isPresented: $isShowingRecurring) { RecurringTemplatesView(store: store) }
        .sheet(isPresented: $isShowingShortcuts) { NavigationStack { TaskShortcutsView().toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { isShowingShortcuts = false } } } } }
        .sheet(item: $editingTask) { task in TaskEditorView(store: store, task: task) }
    }

    private var taskLifecycle: some View {
        editorSheets
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
            await spotlight.reconcile()
        }
    }

    private var participantLifecycle: some View {
        taskLifecycle
        .task(id: scenePhase) {
            if scenePhase == .active { await continuousReminders.observeStatus() }
        }
        .task(id: scenePhase) {
            if scenePhase == .active { await store.observeParticipantChanges() }
        }
        .task(id: scenePhase) {
            if scenePhase == .active { await notifications.observe() }
        }
        .onChange(of: store.allTasks) { _, _ in spotlight.loadStatus() }
        .onChange(of: path) { _, newPath in if sizeClass != .regular { selectedTaskID = newPath.last } }
        .onChange(of: sizeClass) { _, size in
            path = size == .regular ? [] : selectedTaskID.map { [$0] } ?? []
        }
    }

    private var applicationLifecycle: some View {
        participantLifecycle
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await synchronization.loadConfiguration()
                    await opportunities.foreground()
                    await continuousReminders.scan()
                    await store.reload()
                    await loadSavedViews()
                    await spotlight.reconcile()
                }
            } else if phase == .background { opportunities.background() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in continuousReminders.sourceChanged(); calendar.sourceChanged() }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.NSSystemTimeZoneDidChange)) { _ in calendar.sourceChanged(); Task { await notifications.refresh() } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in Task { await store.reload(); calendar.sourceChanged(); await notifications.refresh() } }
    }

    private var calendarWorkspace: some View {
        applicationLifecycle
        .task(id: displaysCalendar) {
            calendar.isDisplayingToday = displaysCalendar
            if displaysCalendar { await calendar.refresh() }
        }
        .task(id: displaysCalendar ? calendar.snapshot?.day?.end : nil) {
            guard displaysCalendar, let next = calendar.snapshot?.day?.end else { return }
            do {
                try await Task.sleep(for: .seconds(max(1, next.timeIntervalSince(store.currentDate))))
                try Task.checkCancellation()
                await calendar.refresh()
                await store.reload()
            } catch {}
        }
    }

    private var displaysCalendar: Bool { scenePhase == .active && store.customView == nil && store.query == .today }

    private func taskList(selection: Binding<UUID?>?) -> some View {
        TaskListView(store: store, selection: selection, calendar: calendar, edit: { editingTask = $0 })
            .navigationTitle(store.customView?.name ?? "Tasks")
            .safeAreaInset(edge: .bottom) {
                if notifications.needsAttention { Button("Review task alerts") { isConfiguringNotifications = true }.padding().accessibilityIdentifier("notification-attention") }
            }
            .toolbar { workspaceToolbar }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    if continuousReminders.status?.active == true && (continuousReminders.status?.paused == true || continuousReminders.error != nil) {
                        Button("Review Reminders import") { isConfiguringContinuousReminders = true }.font(.footnote).padding().accessibilityIdentifier("continuous-reminders-attention")
                    }
                    if let error = spotlight.status?.error ?? spotlight.error {
                        Button { isShowingSpotlight = true } label: { Label("Spotlight needs attention: " + error, systemImage: "magnifyingglass") }.font(.footnote).padding().accessibilityIdentifier("spotlight-attention")
                    }
                    SynchronizationStatusView(synchronization: synchronization, backgroundError: opportunities.backgroundError)
                    if let error = store.error, !store.tasks.isEmpty { errorBanner(error, retry: { Task { await store.reload() } }) }
                    if let sidebarError { errorBanner(sidebarError, retry: { Task { await loadSavedViews() } }) }
                }
            }
    }

    @ToolbarContentBuilder private var workspaceToolbar: some ToolbarContent {
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
                    Button("Spotlight") { isShowingSpotlight = true }.accessibilityIdentifier("spotlight-settings")
                    Button("Task notifications") { isConfiguringNotifications = true }.accessibilityIdentifier("notification-settings")
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
        guard !isCapturing, !isConfiguringNotifications, !isShowingSpotlight, !isConfiguringSync, !isChoosingCustomView, !isShowingShortcuts, !isShowingRecurring, !isDefiningAttributes, !isImportingReminders, !isConfiguringContinuousReminders, editingTask == nil, store.presentedTaskPanels.isEmpty, !store.isSaving else { return nil }
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
