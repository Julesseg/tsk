import SwiftUI
import TskCore
import TskNative
import EventKit

struct ContentView: View {
    private enum WorkspaceTab: Hashable { case view(WorkspaceView), catalog(WorkspaceView), project(TaskProjectSelection), current, capture }

    enum WorkspaceSetting {
        case customViews, recurring, synchronization, notifications, continuousReminders, remindersImport, attributeDefinitions
        #if DEBUG && targetEnvironment(simulator)
        case spotlightDiagnostics
        #endif
    }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
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
    @State private var prefersSidebar: Bool

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private static var navigationDefaults: UserDefaults {
        #if DEBUG && targetEnvironment(simulator)
        let environment = ProcessInfo.processInfo.environment
        if environment["TSK_UI_ISOLATED_SIMULATOR"] == "1",
           let replica = environment["TSK_TEST_REPLICA_NAME"], UUID(uuidString: replica) != nil,
           let defaults = UserDefaults(suiteName: "tsk.navigation.\(replica)") { return defaults }
        #endif
        return .standard
    }

    init(store: TaskStore) {
        _prefersSidebar = State(initialValue: Self.navigationDefaults.bool(forKey: "prefers-sidebar"))
        _store = State(initialValue: store)
        _spotlight = State(initialValue: SpotlightController(store: store))
        _calendar = State(initialValue: TodayCalendarController(manager: store.manager))
        _synchronization = State(initialValue: SynchronizationStore(manager: store.manager, directory: store.directory))
        _opportunities = State(initialValue: SynchronizationOpportunities(manager: store.manager))
        _notifications = State(initialValue: TaskNotificationController(store: store))
        _continuousReminders = State(initialValue: ContinuousReminderController(store: store))
    }

    var body: some View { calendarWorkspace }

    private var presentation: TaskWorkspacePresentation {
        if sizeClass != .regular { return .compact }
        return dynamicTypeSize.isAccessibilitySize ? .accessibilityColumns : .columns
    }

    private var isProjectWorkspace: Bool { store.selectedWorkspaceView == .projects && store.customView == nil }

    private var tabSelection: Binding<WorkspaceView> {
        Binding(get: { store.selectedWorkspaceView }, set: { view in
            if isPad {
                if columnVisibility != .all { columnVisibility = .all }
                let hasUnsavedFilter = store.customView != nil && store.customView?.id == nil
                guard view != store.selectedWorkspaceView || store.projectSelection != .all || hasUnsavedFilter else { return }
            }
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
        Binding(get: {
            if isPad, needsCurrentTab { return .current }
            return .view(store.selectedWorkspaceView)
        }, set: { tab in
            switch tab {
            case .view(let view), .catalog(let view): tabSelection.wrappedValue = view
            case .project(let project):
                tabSelection.wrappedValue = .projects
                openProject(project)
                projectPath.append(project)
            case .current: break
            case .capture: capture()
            }
        })
    }

    private var favoriteViews: [WorkspaceView] { tabsBeforeEditingViews ?? store.workspaceViews.active }

    private var currentProjectTab: TaskProjectSelection? {
        isProjectWorkspace && store.projectSelection != .all ? store.projectSelection : nil
    }

    private var needsCurrentTab: Bool {
        currentProjectTab != nil || !favoriteViews.contains(store.selectedWorkspaceView)
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
                if isPad { iPadNavigation }
                else { iPhoneNavigation }
            }
        }
    }

    private var iPhoneNavigation: some View {
        TabView(selection: workspaceTabSelection) {
            ForEach(favoriteViews) { view in
                Tab(view.title(in: store), systemImage: view.systemImage, value: WorkspaceTab.view(view)) {
                    if view == store.selectedWorkspaceView { workspaceContent }
                }
                .accessibilityIdentifier("tab-" + view.id)
            }
            Tab("New task", systemImage: "plus", value: WorkspaceTab.capture, role: captureTabRole) { EmptyView() }
                .accessibilityIdentifier("new-task")
        }
        .tabViewStyle(.tabBarOnly)
    }

    private func nativeItem(_ view: WorkspaceView, catalog: Bool = false, title: String? = nil) -> NativeWorkspaceNavigation.Item {
        NativeWorkspaceNavigation.Item(id: catalog ? "catalog-" + view.id : view.id,
            title: title ?? view.title(in: store), image: view.systemImage,
            accessibilityIdentifier: (catalog ? "sidebar-view-" : "tab-") + view.id,
            select: { workspaceTabSelection.wrappedValue = catalog ? .catalog(view) : .view(view) })
    }

    private func nativeProjectItem(_ project: TaskProjectSelection) -> NativeWorkspaceNavigation.Item {
        NativeWorkspaceNavigation.Item(id: project.projectName.map { "catalog-project-name-" + Data($0.utf8).base64EncodedString() } ?? "catalog-project-none",
            title: project.projectName ?? "No project", image: "folder",
            accessibilityIdentifier: "sidebar-project-" + (project.projectName ?? "unassigned"),
            select: { workspaceTabSelection.wrappedValue = .project(project) })
    }

    private var iPadNavigation: some View {
        let favorites = favoriteViews.map { nativeItem($0) }
        let current = needsCurrentTab ? NativeWorkspaceNavigation.Item(id: "current-workspace",
            title: currentProjectTab.map { $0.projectName ?? "No project" } ?? store.selectedWorkspaceView.title(in: store),
            image: currentProjectTab != nil ? "folder" : store.selectedWorkspaceView.systemImage,
            accessibilityIdentifier: "current-workspace", select: {}) : nil
        let predefined = NativeWorkspaceNavigation.Section(id: "predefined-catalog", title: "Predefined views",
            items: WorkspaceView.defaults.filter { $0 != .projects }.map { nativeItem($0, catalog: true) })
        let projects = NativeWorkspaceNavigation.Section(id: "projects-catalog", title: "Projects",
            items: [nativeItem(.projects, catalog: true, title: "All projects"), nativeProjectItem(.unassigned)] + store.availableProjects.map { nativeProjectItem(.project($0)) })
        let custom = NativeWorkspaceNavigation.Section(id: "custom-catalog", title: "Custom views",
            items: store.savedViews.map { nativeItem(.custom($0.id), catalog: true) })
        return NativeWorkspaceNavigation(favorites: favorites, current: current,
            sections: [predefined, projects] + (custom.items.isEmpty ? [] : [custom]),
            selection: current?.id ?? store.selectedWorkspaceView.id, content: AnyView(workspaceContent),
            prefersSidebar: prefersSidebar, presentationChanged: { isSidebar in
                if prefersSidebar != isSidebar {
                    prefersSidebar = isSidebar
                    Self.navigationDefaults.set(isSidebar, forKey: "prefers-sidebar")
                }
            }, settings: { isShowingSettings = true })
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
            if !isPad, store.customView != nil && store.customView?.id == nil { captureButton.padding() }
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
        TaskListView(store: store, selection: selection, calendar: calendar, edit: { editingTask = $0 })
            .navigationTitle(title ?? store.customView?.name ?? store.selectedWorkspaceView.title(in: store))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if notifications.needsAttention { Button("Review task alerts") { isConfiguringNotifications = true }.padding().accessibilityIdentifier("notification-attention") }
            }
            .toolbar {
                workspaceTitle(title ?? store.customView?.name ?? store.selectedWorkspaceView.title(in: store))
                if presentation != .columns || isProjectWorkspace { settingsToolbar }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    if continuousReminders.status?.active == true && (continuousReminders.status?.paused == true || continuousReminders.error != nil) {
                        Button("Review Reminders import") { isConfiguringContinuousReminders = true }.font(.footnote).padding().accessibilityIdentifier("continuous-reminders-attention")
                    }
                    if let error = store.error, !store.tasks.isEmpty { errorBanner(error, retry: { Task { await store.reload() } }) }
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
        if isPad {
            ToolbarItem(placement: .topBarTrailing) { viewsMenu }
            ToolbarItem(placement: .topBarTrailing) {
                Button("New task", systemImage: "plus", action: capture)
                    .accessibilityIdentifier("new-task")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Settings", systemImage: "gearshape") { isShowingSettings = true }
                .accessibilityIdentifier("workspace-settings")
        }
    }

    private var viewsMenu: some View {
        Menu("Views", systemImage: "rectangle.stack") {
            Section("Predefined views") {
                ForEach(WorkspaceView.defaults) { view in viewMenuItem(view) }
            }
            Section("Projects") {
                projectMenuItem("No project", selection: .unassigned)
                ForEach(store.availableProjects.map { UTF8String($0) }) { project in
                    projectMenuItem(project.rawValue, selection: .project(project.rawValue))
                }
            }
            if !store.savedViews.isEmpty {
                Section("Custom views") {
                    ForEach(store.savedViews) { view in viewMenuItem(.custom(view.id)) }
                }
            }
            Divider()
            Button("Manage favorites", systemImage: "star", action: presentViews)
                .accessibilityIdentifier("manage-favorite-views")
        }
        .accessibilityIdentifier("workspace-views")
    }

    private func viewMenuItem(_ view: WorkspaceView) -> some View {
        Button { tabSelection.wrappedValue = view } label: {
            if store.selectedWorkspaceView == view && store.projectSelection == .all {
                Label(view.title(in: store), systemImage: "checkmark")
            } else { Label(view.title(in: store), systemImage: view.systemImage) }
        }
        .accessibilityIdentifier("open-view-" + view.id)
    }

    private func projectMenuItem(_ title: String, selection: TaskProjectSelection) -> some View {
        Button { workspaceTabSelection.wrappedValue = .project(selection) } label: {
            if store.selectedWorkspaceView == .projects && store.projectSelection == selection {
                Label(title, systemImage: "checkmark")
            } else { Label(title, systemImage: "folder") }
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
        store.customView == nil && store.query == .upcoming ? store.upcomingDays.flatMap(\.entries).map(\.task) : store.tasks
    }

    private var workspaceActions: TaskWorkspaceActions? {
        guard !isCapturing, !isShowingSettings, pendingWorkspaceSetting == nil, !isConfiguringNotifications, !isConfiguringSync, !isChoosingCustomView, !isShowingRecurring, !isDefiningAttributes, !isImportingReminders, !isConfiguringContinuousReminders, editingTask == nil, store.presentedTaskPanels.isEmpty, !store.isSaving else { return nil }
        #if DEBUG && targetEnvironment(simulator)
        guard !isShowingSpotlightDiagnostics else { return nil }
        #endif
        return TaskWorkspaceActions(
            capture: capture,
            edit: selectedTask.flatMap { task in task.canEdit ? { editingTask = task } : nil },
            complete: selectedTask.flatMap { task in task.canComplete ? { Task { _ = await store.complete(id: task.id) } } : nil },
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
        guard isPad || store.workspaceViews.active.contains(view) else { presentViews(); return }
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
