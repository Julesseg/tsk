import SwiftUI
import TskCore

struct ContentView: View {
    @State private var store = TaskStore()
    @State private var isCapturing = false

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
                    ContentUnavailableView("No tasks yet", systemImage: "checklist", description: Text("Capture a task to get started. Saved tasks stay on this device when you're offline."))
                } else {
                    List(store.tasks) { task in
                        NavigationLink {
                            TaskDetailView(task: task)
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
            .navigationTitle("Tasks")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New task", systemImage: "plus") { isCapturing = true }
                        .accessibilityIdentifier("new-task")
                        .keyboardShortcut("n", modifiers: .command)
                }
            }
            .overlay { if store.isLoading && store.tasks.isEmpty { ProgressView() } }
            .sheet(isPresented: $isCapturing) {
                TaskDraftView(store: store)
            }
            .task { await store.reload() }
        }
    }
}

struct TaskDraftView: View {
    let store: TaskStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft = TaskDraft()
    @State private var error: String?
    @FocusState private var isDescriptionFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("What needs to be done?", text: $draft.description, axis: .vertical)
                        .accessibilityIdentifier("task-description")
                        .focused($isDescriptionFocused)
                }
                Section {
                    Text("Review your task before saving. It will be stored locally and available offline.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(.red).accessibilityIdentifier("draft-error")
                    }
                }
            }
            .navigationTitle("New task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(store.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await store.save(draft) { dismiss() } else { error = store.error }
                        }
                    }
                    .disabled(store.isSaving)
                    .accessibilityIdentifier("save-task")
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .interactiveDismissDisabled(store.isSaving)
            .onAppear { isDescriptionFocused = true }
        }
    }
}

struct TaskDetailView: View {
    let task: TaskRecord

    var body: some View {
        Form {
            Section("Description") { Text(task.description).textSelection(.enabled) }
            Section("Attributes") {
                ForEach(task.attributes.keys.sorted(), id: \.self) { key in
                    LabeledContent(key, value: task.attributes[key] ?? "")
                }
            }
            Section("Identity") { Text(task.id.uuidString).font(.caption).textSelection(.enabled) }
            if task.isRecurring {
                Section { Text("Recurring templates and occurrences are preserved. Editing requires the recurrence editor.").font(.footnote) }
            }
        }
        .navigationTitle("Task")
        .navigationBarTitleDisplayMode(.inline)
    }
}
