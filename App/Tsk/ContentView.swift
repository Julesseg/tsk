import SwiftUI
import TskCore

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: TaskStore
    @State private var synchronization: SynchronizationStore
    @State private var isCapturing = false
    @State private var isConfiguringSync = false
    @State private var editingTask: TaskRecord?

    init() {
        let store = TaskStore()
        _store = State(initialValue: store)
        _synchronization = State(initialValue: SynchronizationStore(manager: store.manager, directory: store.directory))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let error = store.error, store.tasks.isEmpty {
                    ContentUnavailableView {
                        Label("Tasks unavailable", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") { Task { await store.reload() } }
                    }
                } else if store.tasks.isEmpty {
                    ContentUnavailableView(store.query == .upcoming ? "No upcoming plans or deadlines" : store.query == .today ? "Nothing planned or due today" : store.query == .completed ? "No completed tasks" : "No unfinished tasks", systemImage: "checklist", description: Text("Capture a task to get started. Saved tasks stay on this device when you're offline."))
                } else if store.query == .upcoming {
                    UpcomingTaskList(store: store) { editingTask = $0 }
                } else {
                    List(store.tasks) { task in
                        NavigationLink {
                            TaskDetailView(store: store, task: task)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(task.description)
                                if let project = task.attributes["project"], !project.isEmpty {
                                    Text(project).font(.caption).foregroundStyle(.secondary)
                                }
                                TaskPlanningCaption(task: task)
                                TaskAvailabilityView(task: task, store: store)
                                if task.status != "pending" || task.isRecurring {
                                    Text(task.isRecurring ? "Recurring task · read only" : task.status.capitalized)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityIdentifier("task-\(task.id.uuidString)")
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if task.canComplete {
                                Button("Complete", systemImage: "checkmark") {
                                    Task { _ = await store.complete(id: task.id) }
                                }
                                .tint(.green)
                                .disabled(store.isSaving)
                            }
                            if task.canEdit {
                                Button("Edit", systemImage: "pencil") { editingTask = task }
                                    .disabled(store.isSaving)
                            }
                        }
                    }
                    .refreshable { await store.reload() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let error = store.error, !store.tasks.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error).font(.footnote)
                        Button("Retry") { Task { await store.reload() } }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial)
                }
            }
            .safeAreaInset(edge: .top) {
                VStack(spacing: 8) {
                    ProjectPicker(store: store)
                    Picker("Task status", selection: $store.query) {
                    Text("Today").tag(TaskQuery.today)
                    Text("Upcoming").tag(TaskQuery.upcoming)
                    Text("Unfinished").tag(TaskQuery.unfinished)
                    Text("Completed").tag(TaskQuery.completed)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .accessibilityIdentifier("task-status-view")
                }
            }
            .navigationTitle("Tasks")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Synchronization", systemImage: "arrow.triangle.2.circlepath") { isConfiguringSync = true }
                        .accessibilityIdentifier("synchronization-settings")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("New task", systemImage: "plus") { store.query = .unfinished; isCapturing = true }
                        .accessibilityIdentifier("new-task")
                        .keyboardShortcut("n", modifiers: .command)
                }
            }
            .overlay { if store.isLoading && store.tasks.isEmpty { ProgressView() } }
            .sheet(isPresented: $isCapturing) {
                TaskEditorView(store: store)
            }
            .sheet(isPresented: $isConfiguringSync) {
                SyncSettingsView(synchronization: synchronization, tasks: store)
            }
            .sheet(item: $editingTask) { task in TaskEditorView(store: store, task: task) }
            .task(id: TaskListSelection(query: store.query, project: store.projectSelection)) { await store.reload() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await store.reload() } }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                Task { await store.reload() }
            }
            .task { await synchronization.loadConfiguration() }
        }
    }
}

private struct TaskListSelection: Equatable {
    let query: TaskQuery
    let project: TaskProjectSelection
}
