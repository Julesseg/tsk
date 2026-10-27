import SwiftUI
import TskCore
import TskNative
import EventKit

struct ContentView: View {
    private enum WorkspaceTab: Hashable { case view(WorkspaceView), capture }

    enum WorkspaceSetting {
        case customViews, recurring, synchronization, notifications, continuousReminders, remindersImport, attributeDefinitions
        #if DEBUG && targetEnvironment(simulator)
        case spotlightDiagnostics
        #endif
    }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var store: TaskStore
    @State private var synchronization: SynchronizationStore
    @State private var opportunities: SynchronizationOpportunities
    @State private var spotlight: SpotlightController
    #if DEBUG && targetEnvironment(simulator)
    @State private var isShowingSpotlightDiagnostics = false
    #endif
    @State private var calendar: TodayCalendarController
    @State private var notifications: TaskNotificationController
    @State private var isConfiguringNotifications = false
    @State private var continuousReminders: ContinuousReminderController
    @State private var isConfiguringContinuousReminders = false
    @State private var isCapturing = false
    @State private var isConfiguringSync = false
    @State private var isChoosingCustomView = false
    @State private var tabsBeforeEditingViews: [WorkspaceView]?
    @State private var isShowingRecurring = false
    @State private var isDefiningAttributes = false
    @State private var isImportingReminders = false
    @State private var isShowingSettings = false
    @State private var pendingWorkspaceSetting: WorkspaceSetting?
    @State private var editingTask: TaskRecord?
    @State private var selectedTaskID: UUID?
    @State private var path: [UUID] = []
    @State private var sidebarError: String?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var projectPath = NavigationPath()

    init(store: TaskStore) {
        _store = State(initialValue: store)
        _spotlight = State(initialValue: SpotlightController(store: store))
        _calendar = State(initialValue: TodayCalendarController(manager: store.manager))
        _synchronization = State(initialValue: SynchronizationStore(manager: store.manager, directory: store.directory))
        _opportunities = State(initialValue: SynchronizationOpportunities(manager: store.manager))
        _notifications = State(initialValue: TaskNotificationController(store: store))
        _continuousReminders = State(initialValue: ContinuousReminderController(store: store))
    }

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            calendarWorkspace
                .simultaneousGesture(SpatialTapGesture(coordinateSpace: .global).onEnded { tap in
                    guard let editing = store.rowEditing, editing.isExpanded,
                          !editing.bounds.contains(tap.location) else { return }
                    traceTaskRowMenu("outside tap \(tap.location) bounds=\(editing.bounds)", editing: editing)
                    closeRow()
                }, including: store.rowEditing == nil ? .subviews : .all)
                .overlay {
                    TaskRowDismissalOverlay(editing: store.rowEditing, close: { closeRow() })
                }
        }
        .environment(\.taskRowActions, TaskRowActions(close: { closeRow() }, information: { task in closeRow { showInformation(task) } }))
    }

    private func dismissRowParameter() {
        store.rowEditing?.parameter = nil
    }

    private func closeRow(after: (() -> Void)? = nil) {
        guard let editing = store.rowEditing, !editing.isSaving, editing.isExpanded else { return }
        traceTaskRowMenu("closeRow entered", editing: editing)
        if editing.parameter != nil { dismissRowParameter(); return }
        editing.isSaving = true
        Task {
            do {
                let changes = try editing.draft.changes()
                let saved = changes.isEmpty ? editing.draft.original : await store.update(id: editing.draft.original.id, changes: changes)
                guard let saved else {
                    editing.error = store.error
                    editing.isSaving = false
                    return
                }
                editing.savedTask = saved
                await editing.setExpanded(false, reduceMotion: reduceMotion)
                store.rowEditing = nil
                after?()
            } catch { editing.error = error.localizedDescription; editing.isSaving = false }
        }
    }

    private func showInformation(_ task: TaskRecord) {
        selectedTaskID = task.id
        if isProjectWorkspace { projectPath.append(task.id) }
        else if presentation != .columns { path = [task.id] }
    }

    private var presentation: TaskWorkspacePresentation {
        if sizeClass != .regular { return .compact }
        return dynamicTypeSize.isAccessibilitySize ? .accessibilityColumns : .columns
    }

    private var isProjectWorkspace: Bool { store.selectedWorkspaceView == .projects && store.customView == nil }

    private var tabSelection: Binding<WorkspaceView> {
        Binding(get: { store.selectedWorkspaceView }, set: { view in
            resetNavigation()
            store.selectWorkspaceView(view)
        })
    }

    private func resetNavigation() {
        projectPath = NavigationPath()
        selectedTaskID = nil
        path = []
    }

    private var taskNavigationPath: Binding<[UUID]> {
        if presentation == .accessibilityColumns {
            Binding(get: { selectedTaskID.map { [$0] } ?? [] }, set: { selectedTaskID = $0.last })
        } else { $path }
    }

    private var workspaceTabSelection: Binding<WorkspaceTab> {
        Binding(get: { .view(store.selectedWorkspaceView) }, set: { tab in
            switch tab {
            case .view(let view): tabSelection.wrappedValue = view
            case .capture: capture()
            }
        })
    }

    private var captureTabRole: TabRole {
        if #available(iOS 27, *) { .prominent }
        else { .search }
    }

    private var navigationWorkspace: some View {
        Group {
            if !store.workspaceViewsLoaded && sidebarError == nil {
                ProgressView("Loading views")
            } else if store.customView != nil && store.customView?.id == nil {
                workspaceContent
            } else {
                TabView(selection: workspaceTabSelection) {
                    ForEach(tabsBeforeEditingViews ?? store.workspaceViews.active) { view in
                        Tab(view.title(in: store), systemImage: view.systemImage, value: WorkspaceTab.view(view)) {
                            if view == store.selectedWorkspaceView {
                                workspaceContent
                                    .environment(\.horizontalSizeClass, sizeClass)
                            }
                        }
                        .accessibilityIdentifier("tab-" + view.id)
                    }
                    Tab("New task", systemImage: "plus", value: WorkspaceTab.capture, role: captureTabRole) {
                        EmptyView()
                    }
                    .accessibilityIdentifier("new-task")
                }
                .tabViewStyle(.tabBarOnly)
                // Keep the native tab bar at the bottom on iPad while retaining regular content columns.
                .environment(\.horizontalSizeClass, .compact)
            }
        }
    }

    private var workspaceContent: some View {
        Group {
            if isProjectWorkspace {
                projectsWorkspace
            } else {
                tasksWorkspace
            }
        }
        .safeAreaInset(edge: .bottom, alignment: .trailing) {
            if store.customView != nil && store.customView?.id == nil { captureButton.padding() }
        }
    }

    private var captureButton: some View {
        Button(action: capture) {
            Image(systemName: "plus")
                .font(.title2)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel("New task")
        .accessibilityIdentifier("new-task")
    }

    @ViewBuilder private var tasksWorkspace: some View {
        if presentation == .columns {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                taskList(selection: $selectedTaskID)
                    .navigationSplitViewColumnWidth(min: 260, ideal: 360, max: 480)
            } detail: {
                selectedTaskDetail
            }
            .navigationSplitViewStyle(.balanced)
            .accessibilityIdentifier("task-workspace")
        } else {
            NavigationStack(path: taskNavigationPath) {
                taskList(selection: presentation == .accessibilityColumns ? $selectedTaskID : nil)
                    .navigationDestination(for: UUID.self) { id in taskDestination(id) }
            }
            .accessibilityIdentifier("workspace-accessibility-navigation")
        }
    }

    private var projectsWorkspace: some View {
        NavigationStack(path: $projectPath) {
            List {
                projectLink("No project", selection: .unassigned)
                ForEach(store.availableProjects.map { UTF8String($0) }) { project in
                    projectLink(project.rawValue, selection: .project(project.rawValue))
                }
                if store.availableProjects.isEmpty {
                    Text("Add a project when creating or editing a task.")
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("projects-list")
            .navigationTitle("Projects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                workspaceTitle("Projects")
                settingsToolbar
            }
            .navigationDestination(for: TaskProjectSelection.self) { project in
                taskList(selection: nil, title: project.projectName ?? "No project")
                    .onAppear { openProject(project) }
            }
            .navigationDestination(for: UUID.self) { id in
                taskDestination(id).onAppear { selectedTaskID = id }
            }
        }
        .onChange(of: projectPath) { _, value in
            if value.isEmpty { store.projectSelection = .all }
            if value.count < 2 { selectedTaskID = nil }
        }
    }

    private func projectLink(_ title: String, selection: TaskProjectSelection) -> some View {
        NavigationLink(value: selection) { Label(title, systemImage: "folder") }
            .accessibilityIdentifier("project-" + title)
    }

    private var selectedTaskDetail: some View {
        Group {
            if let task = selectedTask {
                TaskDetailView(store: store, task: task, edit: { editingTask = $0 })
                    .id(task.id)
            } else {
                ContentUnavailableView("Select a task", systemImage: "sidebar.right", description: Text("Choose a task to review its details, edit it, or mark it complete."))
                    .accessibilityIdentifier("workspace-detail-empty")
            }
        }
        .toolbar { settingsToolbar }
    }

    @ViewBuilder private func taskDestination(_ id: UUID) -> some View {
        if let task = store.allTasks.first(where: { $0.id == id }) {
            TaskDetailView(store: store, task: task, edit: { editingTask = $0 })
        } else {
            ContentUnavailableView("Task unavailable", systemImage: "questionmark.folder")
        }
    }

    private var integrationSheets: some View {
        navigationWorkspace
        .taskKeyboardCommands(workspaceActions?.keyboardCommands ?? TaskKeyboardCommand.suspended)
        #if DEBUG && targetEnvironment(simulator)
        .sheet(isPresented: $isShowingSpotlightDiagnostics) { SpotlightStatusView(controller: spotlight) }
        #endif
        .sheet(isPresented: $isConfiguringNotifications) { TaskNotificationSettingsView(controller: notifications) }
        .sheet(isPresented: $isConfiguringContinuousReminders) { ContinuousReminderSettingsView(controller: continuousReminders).onAppear { TaskUIBoundaryDiagnostics.event("workspace.sheet.appeared", details: ["destination": "continuous-reminders"]) } }
        .sheet(isPresented: $isImportingReminders) { ReminderImportView(store: store).onAppear { TaskUIBoundaryDiagnostics.event("workspace.sheet.appeared", details: ["destination": "reminders-import"]) } }
        .sheet(isPresented: $isDefiningAttributes) { TaskAttributeDefinitionsView(store: store).onAppear { TaskUIBoundaryDiagnostics.event("workspace.sheet.appeared", details: ["destination": "attribute-definitions"]) } }
    }

    private var editorSheets: some View {
        integrationSheets
        .sheet(isPresented: $isCapturing) { TaskEditorView(store: store) }
        .sheet(isPresented: $isChoosingCustomView, onDismiss: {
            tabsBeforeEditingViews = nil
            Task { await loadSavedViews() }
        }) {
            CustomViewsView(store: store, select: {
                tabsBeforeEditingViews = nil
                tabSelection.wrappedValue = $0
            })
        }
        .sheet(isPresented: $isConfiguringSync) {
            SyncSettingsView(synchronization: synchronization, tasks: store, backgroundError: opportunities.backgroundError)
        }
        .sheet(isPresented: $isShowingRecurring) { RecurringTemplatesView(store: store) }
        .sheet(isPresented: $isShowingSettings, onDismiss: presentPendingWorkspaceSetting) {
            TaskSettingsView(calendar: calendar, choose: chooseWorkspaceSetting)
        }
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
        .task(id: scenePhase) {
            if scenePhase == .active { await spotlight.observe() }
        }
        .onChange(of: store.allTasks) { _, _ in Task { await spotlight.reconcile(force: false) } }
        .onChange(of: store.selectedWorkspaceView) { _, _ in resetNavigation() }
        .onChange(of: path) { _, newPath in if presentation != .columns || isProjectWorkspace { selectedTaskID = newPath.last } }
        .onChange(of: presentation) { previous, current in
            if previous != .columns { selectedTaskID = path.last ?? selectedTaskID }
            path = current != .columns ? selectedTaskID.map { [$0] } ?? [] : []
        }
    }

    private var applicationLifecycle: some View {
        participantLifecycle
        .onChange(of: scenePhase) { _, phase in
            TaskUIBoundaryDiagnostics.event("calendar.scene", details: ["phase": String(describing: phase)])
            #if DEBUG && targetEnvironment(simulator)
            continuousReminders.source.recordAccessDiagnostic("reminders.scene", details: ["phase": String(describing: phase)])
            #endif
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

    private func taskList(selection: Binding<UUID?>?, title: String? = nil) -> some View {
        TaskListView(store: store, selection: selection, calendar: calendar, edit: { showInformation($0) })
            .navigationTitle(title ?? store.customView?.name ?? store.selectedWorkspaceView.title(in: store))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                workspaceTitle(title ?? store.customView?.name ?? store.selectedWorkspaceView.title(in: store))
                if presentation != .columns || isProjectWorkspace { settingsToolbar }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    if continuousReminders.status?.active == true && (continuousReminders.status?.paused == true || continuousReminders.error != nil) {
                        Button("Review Reminders import") { isConfiguringContinuousReminders = true }.font(.footnote).padding().accessibilityIdentifier("continuous-reminders-attention")
                    }
                    if let error = store.error, !store.tasks.isEmpty, store.rowEditing == nil { errorBanner(error, retry: { Task { await store.reload() } }) }
                    if let sidebarError { errorBanner(sidebarError, retry: { Task { await loadSavedViews() } }) }
                }
            }
    }

    @ToolbarContentBuilder private func workspaceTitle(_ title: String) -> some ToolbarContent {
        ToolbarItem(placement: .title) {
            WorkspaceTitleView(title: title, isSyncing: synchronization.isSyncing)
                .font(.headline)
        }
    }

    @ToolbarContentBuilder private var settingsToolbar: some ToolbarContent {
        if store.customView != nil && store.customView?.id == nil {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close filter", systemImage: "xmark") { tabSelection.wrappedValue = store.selectedWorkspaceView }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Settings", systemImage: "gearshape") { isShowingSettings = true }
                .accessibilityIdentifier("workspace-settings")
        }
    }

    private func chooseWorkspaceSetting(_ destination: WorkspaceSetting) {
        guard isShowingSettings, pendingWorkspaceSetting == nil else { return }
        pendingWorkspaceSetting = destination
        isShowingSettings = false
    }

    private func presentPendingWorkspaceSetting() {
        guard let destination = pendingWorkspaceSetting else { return }
        pendingWorkspaceSetting = nil
        switch destination {
        case .customViews: presentViews()
        case .recurring: isShowingRecurring = true
        case .synchronization: isConfiguringSync = true
        case .notifications:
            TaskParticipantDiagnostics.event("notifications.presentation.request", details: ["source": "settings"])
            isConfiguringNotifications = true
        case .continuousReminders: requestIntegrationPresentation("continuous-reminders", state: $isConfiguringContinuousReminders)
        case .remindersImport: requestIntegrationPresentation("reminders-import", state: $isImportingReminders)
        case .attributeDefinitions: requestIntegrationPresentation("attribute-definitions", state: $isDefiningAttributes)
        #if DEBUG && targetEnvironment(simulator)
        case .spotlightDiagnostics: isShowingSpotlightDiagnostics = true
        #endif
        }
    }

    private func presentViews() {
        tabsBeforeEditingViews = store.workspaceViews.active
        isChoosingCustomView = true
    }

    private func requestIntegrationPresentation(_ destination: String, state: Binding<Bool>) {
        TaskUIBoundaryDiagnostics.event("workspace.menu.action-entry", details: ["destination": destination, "presented": String(state.wrappedValue)])
        state.wrappedValue = true
        TaskUIBoundaryDiagnostics.event("workspace.menu.state-assigned", details: ["destination": destination, "presented": String(state.wrappedValue)])
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
        store.customView == nil && store.query == .upcoming ? store.upcomingDays.flatMap(\.entries).map(\.task) : store.visibleTasks
    }

    private var workspaceActions: TaskWorkspaceActions? {
        guard !isCapturing, !isShowingSettings, pendingWorkspaceSetting == nil, !isConfiguringNotifications, !isConfiguringSync, !isChoosingCustomView, !isShowingRecurring, !isDefiningAttributes, !isImportingReminders, !isConfiguringContinuousReminders, editingTask == nil, store.rowEditing == nil, store.presentedTaskPanels.isEmpty, !store.isSaving else { return nil }
        #if DEBUG && targetEnvironment(simulator)
        guard !isShowingSpotlightDiagnostics else { return nil }
        #endif
        return TaskWorkspaceActions(
            capture: capture,
            edit: selectedTask.flatMap { task in task.canEdit ? { store.expandRow(task) } : nil },
            complete: selectedTask.flatMap { task in task.canComplete ? { Task { _ = await store.completeFromList(id: task.id, animated: !reduceMotion) } } : nil },
            move: moveSelection,
            reveal: selectedTask.map { task in {
                if isProjectWorkspace { projectPath.append(task.id) }
                else if presentation != .columns { path = [task.id] }
            } },
            openView: openView,
            refresh: { Task { await store.reload() } }
        )
    }

    private func capture() {
        if store.customView == nil, store.selectedWorkspaceView != .projects, store.workspaceViews.active.contains(.unfinished) {
            tabSelection.wrappedValue = .unfinished
        }
        isCapturing = true
    }

    private func openView(_ query: TaskQuery) {
        guard let view = WorkspaceView.defaults.first(where: { $0.query == query }) else { return }
        guard store.workspaceViews.active.contains(view) else { presentViews(); return }
        tabSelection.wrappedValue = view
    }

    private func openProject(_ project: TaskProjectSelection) {
        guard isProjectWorkspace else { return }
        store.query = .unfinished
        store.projectSelection = project
    }

    private func moveSelection(_ movement: TaskSelectionMovement) {
        selectedTaskID = store.manager.selectedTask(in: navigationRows, from: selectedTaskID, moving: movement)
        if presentation != .columns, !path.isEmpty { path = selectedTaskID.map { [$0] } ?? [] }
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

private enum TaskWorkspacePresentation: Equatable {
    case columns, accessibilityColumns, compact
}

private struct TaskRowDismissalOverlay: View {
    let editing: TaskRowEditing?
    let close: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            if let editing, editing.isExpanded, editing.bounds != .zero {
                let origin = geometry.frame(in: .global).origin
                TaskRowDismissal(bounds: editing.bounds.offsetBy(dx: -origin.x, dy: -origin.y), size: geometry.size, close: close)
                    .allowsHitTesting(false)
            }
        }
        .background {
            GeometryReader { geometry in
                if let editing, editing.bounds != .zero {
                    let origin = geometry.frame(in: .global).origin
                    let bounds = editing.bounds.offsetBy(dx: -origin.x, dy: -origin.y)
                    let viewport = editing.viewport.offsetBy(dx: -origin.x, dy: -origin.y)
                    Path { path in
                        path.addRect(CGRect(origin: .zero, size: geometry.size))
                        path.addPath(Path(roundedRect: bounds, cornerRadius: 18).intersection(Path(viewport)))
                    }
                    .fill((colorScheme == .dark ? Color.white : Color.black).opacity(0.08 * editing.revealProgress), style: FillStyle(eoFill: true))
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
