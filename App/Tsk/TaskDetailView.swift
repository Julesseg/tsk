import SwiftUI
import TskCore

struct TaskDetailView: View {
    let store: TaskStore
    @State private var task: TaskRecord
    @State private var isEditing = false

    init(store: TaskStore, task: TaskRecord) {
        self.store = store
        _task = State(initialValue: task)
    }

    var body: some View {
        Form {
            Section("Description") { Text(task.description).textSelection(.enabled) }
            TaskOrganizationSummary(task: task)
            Section {
                LabeledContent("Status", value: task.status.capitalized)
                if task.canComplete {
                    Button("Complete task", systemImage: "checkmark.circle") {
                        Task { if let completed = await store.complete(id: task.id) { task = completed } }
                    }
                    .disabled(store.isSaving)
                    .accessibilityIdentifier("complete-task")
                }
            }
            TaskAvailabilityView(task: task, store: store, isDetail: true)
            TaskDependenciesSection(store: store, task: task, onSave: { task = $0 })
            Section("Planning") { TaskPlanningSummary(task: task) }
            Section("Attributes") {
                ForEach(task.attributes.keyIdentities) { key in
                    LabeledContent(key.rawValue, value: task.attributes[key.rawValue] ?? "")
                }
            }
            Section("Identity") { Text(task.id.uuidString).font(.caption).textSelection(.enabled) }
            if !task.canEdit {
                Section { Text("These task attributes are preserved. Recurring tasks and unsupported states require their dedicated editor.").font(.footnote) }
            }
            if let error = store.error {
                Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("task-action-error") }
            }
        }
        .navigationTitle("Task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if task.canEdit {
                Button("Edit") { isEditing = true }
                    .disabled(store.isSaving)
                    .accessibilityIdentifier("edit-task")
                    .keyboardShortcut("e", modifiers: .command)
            }
        }
        .sheet(isPresented: $isEditing) { TaskEditorView(store: store, task: task, onSave: { task = $0 }) }
        .onChange(of: isEditing) { _, editing in
            if !editing {
                Task {
                    do { task = try await store.manager.task(id: task.id) }
                    catch { store.error = error.localizedDescription }
                }
            }
        }
        .onChange(of: store.allTasks) { _, tasks in
            if let updated = tasks.first(where: { $0.id == task.id }) { task = updated }
        }
    }
}
