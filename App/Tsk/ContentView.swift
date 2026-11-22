import SwiftUI
import TskCore
import TskNative
import EventKit

struct ContentView: View {
    enum WorkspaceSetting {
        case recurring, synchronization
    }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(TaskURLController.self) private var automation
    @State private var dayPaging = TaskDayPaging()
    @State private var store: TaskStore
    @State private var synchronization: SynchronizationStore
    @State private var opportunities: SynchronizationOpportunities
    @State private var calendar: TodayCalendarController
    @State private var isConfiguringSync = false
    @State private var isShowingRecurring = false
    @State private var isShowingSettings = false
    @State private var pendingWorkspaceSetting: WorkspaceSetting?
    @State private var selectedTaskID: UUID?
    @State private var path: [UUID] = []
    @State private var linkedTaskPresentationID = UUID()
    @State private var projectPath = NavigationPath()
    @State private var taskActionReturnPaths: (tasks: [UUID], projects: NavigationPath, selected: UUID?)?
    @State private var isRequestingCapture = false

    init(store: TaskStore) {
        _store = State(initialValue: store)
        _calendar = State(initialValue: TodayCalendarController(manager: store.manager))
        _synchronization = State(initialValue: SynchronizationStore(manager: store.manager, directory: store.directory))
        _opportunities = State(initialValue: SynchronizationOpportunities(manager: store.manager))
    }

    var body: some View {
        calendarWorkspace
            .simultaneousGesture(SpatialTapGesture(coordinateSpace: .global).onEnded { tap in
                guard let editing = store.rowEditing, editing.isExpanded,
                      tap.location.y < editing.viewport.maxY,
                      !editing.bounds.contains(tap.location) else { return }
                closeRow()
            }, including: store.rowEditing == nil ? .subviews : .all)
            .overlay {
                TaskRowDismissalOverlay(editing: store.rowEditing, close: { closeRow() })
            }
            .overlay {
                if dayPaging.expanded {
                    PlannerCalendarDismissal(paging: dayPaging) {
                        dayPaging.expanded = false
                    }
                    .ignoresSafeArea(.container)
                }
            }
            .environment(\.taskRowActions, TaskRowActions(close: { closeRow() }))
    }

    private func closeRow(after: (() -> Void)? = nil) {
        guard let editing = store.rowEditing else { return }
        Task {
            guard !isRequestingCapture else { return }
            if await editing.saveAndCollapse(in: store, reduceMotion: reduceMotion) { after?() }
        }
    }

    private func showLinkedTask(_ task: TaskRecord) {
        selectedTaskID = task.id
        if isProjectWorkspace { projectPath.append(task.id) }
        else { path = [task.id] }
    }

    private var isProjectWorkspace: Bool { store.selectedWorkspaceView == .projects }

    private var workspaceSelection: Binding<WorkspaceView> {
        Binding(get: { store.selectedWorkspaceView }, set: { view in
            let select = {
                resetNavigation()
                store.selectWorkspaceView(view)
            }
            if store.rowEditing != nil { closeRow(after: select) }
            else { select() }
        })
    }

    private func resetNavigation() {
        projectPath = NavigationPath()
        selectedTaskID = nil
        path = []
    }

    private var workspaceContent: some View {
        Group {
            if isProjectWorkspace {
                projectsWorkspace
            } else {
                tasksWorkspace
            }
        }
    }

    private var workspaceControls: TaskWorkspaceControls {
        TaskWorkspaceControls(workspace: store.navigationReturn == nil ? workspaceSelection : nil, capture: capture)
    }

    private var tasksWorkspace: some View {
        NavigationStack(path: $path) {
            taskList()
                .navigationDestination(for: UUID.self) { id in taskDestination(id) }
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
            .safeAreaInset(edge: .bottom, spacing: 0) { workspaceControls }
            .accessibilityIdentifier("projects-list")
            .navigationTitle("Projects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                workspaceTitle("Projects")
                settingsToolbar
            }
            .navigationDestination(for: TaskProjectSelection.self) { project in
                taskList(title: project.projectName ?? "No project")
                    .onAppear { openProject(project) }
            }
            .navigationDestination(for: UUID.self) { id in
                taskDestination(id).onAppear { selectedTaskID = id }
            }
        }
        .onChange(of: projectPath) { _, value in
            guard isProjectWorkspace else { return }
            if value.isEmpty { store.projectSelection = .all }
            if value.count < 2 { selectedTaskID = nil }
        }
    }

    private func projectLink(_ title: String, selection: TaskProjectSelection) -> some View {
        NavigationLink(value: selection) { Label(title, systemImage: "folder") }
            .accessibilityIdentifier("project-" + title)
    }

    @ViewBuilder private func taskDestination(_ id: UUID) -> some View {
        TaskLinkedTaskList(source: store, taskID: id)
            .id(linkedTaskPresentationID)
            .safeAreaInset(edge: .bottom, spacing: 0) { TaskWorkspaceControls(workspace: nil, capture: capture) }
    }

    private var editorSheets: some View {
        workspaceContent
        .sheet(isPresented: $isConfiguringSync) {
            SyncSettingsView(synchronization: synchronization, tasks: store, backgroundError: opportunities.backgroundError).modifier(TaskWorkspacePanel(store: store))
        }
        .sheet(isPresented: $isShowingRecurring) { RecurringTemplatesView(store: store).modifier(TaskWorkspacePanel(store: store)) }
        .sheet(isPresented: $isShowingSettings, onDismiss: presentPendingWorkspaceSetting) {
            TaskSettingsView(calendar: calendar, choose: chooseWorkspaceSetting).modifier(TaskWorkspacePanel(store: store))
        }
    }

    private var taskLifecycle: some View {
        editorSheets
        .task(id: TaskListSelection(external: store.navigationReturn != nil, query: store.query, project: store.projectSelection, day: store.isDayPage ? store.displayedDay : nil)) {
            if store.navigationReturn == nil, let previous = taskActionReturnPaths {
                path = previous.tasks
                projectPath = previous.projects
                selectedTaskID = previous.selected
                taskActionReturnPaths = nil
            } else {
                selectedTaskID = nil
                path = []
            }
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
            opportunities.start()
            await opportunities.foreground()
        }
    }

    private var participantLifecycle: some View {
        taskLifecycle
        .task(id: automation.taskToOpen?.id) {
            guard let task = automation.taskToOpen else { return }
            await store.reload()
            guard !Task.isCancelled else { return }
            linkedTaskPresentationID = UUID()
            showLinkedTask(task)
            automation.taskToOpen = nil
        }
        .task {
            automation.navigate = { destination in
                automation.findResults = nil
                if store.navigationReturn == nil {
                    taskActionReturnPaths = (path, projectPath, selectedTaskID)
                }
                resetNavigation()
                try await store.openNavigation(destination)
            }
            ForegroundTaskNavigation.shared.connect { action in
                try await automation.openForeground(action, in: store)
            }
            await automation.executePending(in: store)
        }
        .task(id: scenePhase) {
            if scenePhase == .active { await store.observeParticipantChanges() }
        }
        .onChange(of: automation.deletedTaskID) { _, id in
            if let id, selectedTaskID == id {
                resetNavigation()
            }
        }
        .onChange(of: path) { _, newPath in selectedTaskID = newPath.last }
    }

    private var applicationLifecycle: some View {
        participantLifecycle
        .onChange(of: scenePhase) { _, phase in
            TaskUIBoundaryDiagnostics.event("calendar.scene", details: ["phase": String(describing: phase)])
            if phase == .active {
                Task {
                    await synchronization.loadConfiguration()
                    await opportunities.foreground()
                    await store.reload()
                }
            } else if phase == .background { opportunities.background() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in calendar.sourceChanged() }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.NSSystemTimeZoneDidChange)) { _ in calendar.sourceChanged() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in Task { await store.reload(); calendar.sourceChanged() } }
    }

    private var calendarWorkspace: some View {
        applicationLifecycle
        .task(id: displaysCalendar ? store.displayedDay : nil) {
            calendar.isDisplayingToday = displaysCalendar
            calendar.displayedDay = store.isDayPage ? store.displayedDay : nil
            if displaysCalendar { await calendar.refresh() }
        }
        .task(id: scenePhase == .active ? store.nextDayBoundary : nil) {
            guard scenePhase == .active, let next = store.nextDayBoundary else { return }
            do {
                try await Task.sleep(for: .seconds(max(1, next.timeIntervalSince(store.currentDate))))
                try Task.checkCancellation()
                await store.reload()
                if displaysCalendar { await calendar.refresh() }
            } catch {}
        }
    }

    private var displaysCalendar: Bool {
        scenePhase == .active && store.isDayPage
    }

    private var dayPageTitle: String? {
        guard store.isDayPage else { return nil }
        return Calendar.autoupdatingCurrent.isDate(store.displayedDay, inSameDayAs: store.currentDate)
            ? "Today" : store.displayedDay.formatted(.dateTime.weekday(.wide).day().month())
    }

    private func taskList(title: String? = nil) -> some View {
        TaskListView(store: store, calendar: calendar, dayPaging: dayPaging, workspaceControls: workspaceControls)
            .navigationTitle(title ?? dayPageTitle ?? store.navigationTitle ?? store.selectedWorkspaceView.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                workspaceTitle(title ?? dayPageTitle ?? store.navigationTitle ?? store.selectedWorkspaceView.title)
                settingsToolbar
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    if let saved = store.captureConfirmation {
                        Label("Saved: " + saved.description, systemImage: "checkmark.circle.fill")
                            .font(.callout).padding(8)
                            .accessibilityIdentifier("capture-confirmation")
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                    if let error = store.error, !store.isSelectingTasks, !store.tasks.isEmpty, store.rowEditing == nil, selectedTaskID == nil { errorBanner(error, retry: { Task { await store.reload() } }) }
                }
            }
    }

    @ToolbarContentBuilder private func workspaceTitle(_ title: String) -> some ToolbarContent {
        if store.navigationReturn != nil {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back", systemImage: "chevron.backward") {
                    Task { _ = await store.returnFromNavigation() }
                }
                .accessibilityIdentifier("back-from-task-action")
            }
        }
        ToolbarItem(placement: .title) {
            WorkspaceTitleView(title: title, isSyncing: synchronization.isSyncing)
                .font(.headline)
        }
    }

    @ToolbarContentBuilder private var settingsToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if store.isSelectingTasks {
                Button("Cancel selection", systemImage: "xmark") {
                    guard !store.isSelectionGestureActive else { return }
                    store.endTaskSelection()
                }
                    .labelStyle(.iconOnly)
                    .tint(.primary)
                    .disabled(store.isSaving)
                    .allowsHitTesting(!store.isSelectionGestureActive)
                    .accessibilityIdentifier("cancel-task-selection")
            } else {
                Button("Settings", systemImage: "gearshape") { isShowingSettings = true }
                    .accessibilityIdentifier("workspace-settings")
            }
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
        case .recurring: isShowingRecurring = true
        case .synchronization: isConfiguringSync = true
        }
    }

    private func errorBanner(_ error: String, retry: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(error).font(.footnote)
            Button("Retry", action: retry)
        }
        .padding().frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial)
    }

    private func capture() {
        guard !isRequestingCapture else { return }
        isRequestingCapture = true
        if store.rowEditing == nil {
            selectedTaskID = nil
            if isProjectWorkspace {
                if projectPath.isEmpty {
                    store.projectSelection = .unassigned
                    projectPath.append(TaskProjectSelection.unassigned)
                } else {
                    projectPath = NavigationPath([store.projectSelection])
                }
            } else {
                path = []
            }
        }
        Task {
            await store.beginCapture(reduceMotion: reduceMotion)
            await Task.yield()
            isRequestingCapture = false
        }
    }

    private func openProject(_ project: TaskProjectSelection) {
        guard isProjectWorkspace else { return }
        store.query = .unfinished
        store.projectSelection = project
    }
}

private struct TaskListSelection: Equatable {
    let external: Bool
    let query: TaskQuery
    let project: TaskProjectSelection
    let day: Date?
}

struct TaskRowDismissalOverlay: View {
    let editing: TaskRowEditing?
    let close: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            if let editing, editing.isExpanded, editing.bounds != .zero {
                let origin = geometry.frame(in: .global).origin
                let height = max(0, min(geometry.size.height, editing.viewport.maxY - origin.y))
                TaskRowDismissal(bounds: editing.bounds.offsetBy(dx: -origin.x, dy: -origin.y),
                                 size: CGSize(width: geometry.size.width, height: height), close: close)
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

private struct PlannerCalendarDismissal: UIViewRepresentable {
    let paging: TaskDayPaging
    let dismiss: () -> Void

    func makeUIView(context: Context) -> DismissButton {
        let button = DismissButton()
        button.accessibilityLabel = "Close month calendar"
        button.accessibilityIdentifier = "dismiss-planner-calendar"
        button.addTarget(button, action: #selector(DismissButton.closeCalendar), for: .touchUpInside)
        return button
    }

    func updateUIView(_ button: DismissButton, context: Context) {
        button.paging = paging
        button.dismiss = dismiss
    }

    final class DismissButton: UIButton {
        weak var paging: TaskDayPaging?
        var dismiss: (() -> Void)?

        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            super.point(inside: point, with: event) && paging?.navigatorBounds.contains(convert(point, to: nil)) != true
        }

        override var accessibilityFrame: CGRect {
            get {
                guard let window, let paging else { return super.accessibilityFrame }
                let top = convert(CGPoint(x: 0, y: paging.navigatorBounds.minY), from: window).y
                return UIAccessibility.convertToScreenCoordinates(bounds.divided(atDistance: max(0, top), from: .minYEdge).slice, in: self)
            }
            set { super.accessibilityFrame = newValue }
        }

        @objc func closeCalendar() { dismiss?() }
    }
}
