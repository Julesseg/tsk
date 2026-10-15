import SwiftUI
import TskCore

struct TaskDetailView: View {
    let store: TaskStore
    let edit: ((TaskRecord) -> Void)?
    @State private var task: TaskRecord
    @State private var isEditing = false
    @State private var panel: TaskDetailPanel?

    init(store: TaskStore, task: TaskRecord, edit: ((TaskRecord) -> Void)? = nil) {
        self.store = store
        self.edit = edit
        _task = State(initialValue: task)
    }

    var body: some View {
        Form {
            Section("Description") { Text(task.description).textSelection(.enabled).accessibilityIdentifier("task-detail-description") }
            TaskOrganizationSummary(task: task)
            TaskRecurrenceSection(task: task, store: store)
            Section {
                LabeledContent("Status", value: task.status.capitalized)
                    .accessibilityIdentifier("task-detail-status")
                if task.canComplete {
                    Button(task.isOccurrence ? "Complete occurrence" : "Complete task", systemImage: "checkmark.circle") {
                        Task { if let completed = await store.complete(id: task.id) { task = completed } }
                    }
                    .disabled(store.isSaving)
                    .accessibilityIdentifier("complete-task")
                }
            }
            TaskAvailabilityView(task: task, store: store, isDetail: true)
            TaskDependenciesSection(store: store, task: task, onSave: { task = $0 }, select: { panel = .dependency })
            Section("Planning") { TaskPlanningSummary(task: task) }
            TaskAnnotationsSection(store: store, task: task, edit: { panel = .annotation($0) })
            TaskAdvancedAttributesSection(store: store, task: task, edit: { panel = .attributes })
            Section("Attributes") {
                ForEach(task.attributes.keyIdentities) { key in
                    LabeledContent(key.rawValue, value: task.attributes[key.rawValue] ?? "")
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(key.rawValue)
                        .accessibilityValue(task.attributes[key.rawValue] ?? "")
                        .accessibilityIdentifier("raw-attribute-\(key.rawValue)")
                }
            }
            Section("Identity") { Text(task.id.uuidString).font(.caption).textSelection(.enabled) }
            if !task.canEdit, task.recurrenceInspection == nil {
                Section { Text("These task attributes are preserved. Recurring tasks and unsupported states require their dedicated editor.").font(.footnote) }
            }
            if let error = store.error {
                Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("task-action-error") }
            }
        }
        .accessibilityIdentifier("task-detail-form")
        .navigationTitle("Task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if task.canEdit {
                Button(task.isOccurrence ? "Edit occurrence" : "Edit") {
                    if let edit { edit(task) } else { isEditing = true }
                }
                    .disabled(store.isSaving)
                    .accessibilityIdentifier("edit-task")
                    .keyboardShortcut(edit == nil ? KeyboardShortcut("e", modifiers: .command) : nil)
            }
        }
        .sheet(isPresented: $isEditing) { TaskEditorView(store: store, task: task, onSave: { task = $0 }) }
        .sheet(item: $panel) { panel in
            switch panel {
            case .dependency: TaskDependencySelection(store: store, task: task, onSave: { task = $0 })
            case .annotation(let annotation): TaskAnnotationEditor(store: store, task: task, original: annotation, onSave: { task = $0 })
            case .attributes: TaskAdvancedAttributesEditor(store: store, task: task, onSave: { task = $0 })
            }
        }
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

private enum TaskDetailPanel: Identifiable {
    case dependency, annotation(TaskAnnotation?), attributes

    var id: String {
        switch self {
        case .dependency: "dependency"
        case .annotation(let annotation): annotation?.reference.rawValue ?? "new-annotation"
        case .attributes: "attributes"
        }
    }
}
