import SwiftUI
import TskCore

struct ContentView: View {
    @State private var store = TaskStore()
    @State private var isCapturing = false
    @State private var editingTask: TaskRecord?

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
                    ContentUnavailableView(store.query == .completed ? "No completed tasks" : "No unfinished tasks", systemImage: "checklist", description: Text("Capture a task to get started. Saved tasks stay on this device when you're offline."))
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
                Picker("Task status", selection: $store.query) {
                    Text("Unfinished").tag(TaskQuery.unfinished)
                    Text("Completed").tag(TaskQuery.completed)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .accessibilityIdentifier("task-status-view")
            }
            .navigationTitle("Tasks")
            .toolbar {
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
            .sheet(item: $editingTask) { task in TaskEditorView(store: store, task: task) }
            .task(id: store.query) { await store.reload() }
        }
    }
}
