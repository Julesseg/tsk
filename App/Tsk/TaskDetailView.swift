import SwiftUI
import TskCore

struct TaskDetailView: View {
    let store: TaskStore
    let edit: ((TaskRecord) -> Void)?
    @State private var task: TaskRecord
    @State private var isEditing = false
    @State private var panel: TaskDetailPanel?
    @State private var createdSuccessor: TaskRecord?

    init(store: TaskStore, task: TaskRecord, edit: ((TaskRecord) -> Void)? = nil) {
        self.store = store
        self.edit = edit
        _task = State(initialValue: task)
    }

    var body: some View {
        Form {
            Section("Description") { Text(task.description).textSelection(.enabled).accessibilityIdentifier("task-detail-description") }
            TaskOrganizationSummary(task: task)
            TaskRecurrenceSection(task: task, store: store, transition: { panel = .transition })
            if let createdSuccessor {
                Section("Separate successor created") { NavigationLink("View new recurring template") { TaskDetailView(store: store, task: createdSuccessor) }.accessibilityIdentifier("view-transition-successor") }
            }
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
            Section("Activity") {
                if !task.isActive { Text("Not active").accessibilityIdentifier("task-activity-inactive") }
                TaskActivityCaption(task: task)
                TaskActivityButton(task: task, store: store, isDetail: true, onSave: { task = $0 })
                if !task.canChangeActivity { Text("Start and stop are available for unfinished tasks with valid task state.").font(.footnote) }
            }
            TaskAvailabilityView(task: task, store: store, isDetail: true)
            TaskDependenciesSection(store: store, task: task, onSave: { task = $0 }, select: { panel = .dependency })
            Section("Planning") { TaskPlanningSummary(task: task) }
            TaskAnnotationsSection(store: store, task: task, edit: { panel = .annotation($0) })
            TaskAdvancedAttributesSection(store: store, task: task, edit: { panel = .attributes })
            if !task.canEdit, task.recurrenceInspection == nil {
                Section { Text("These task attributes are preserved. Recurring tasks and unsupported states require their dedicated editor.").font(.footnote) }
            }
        }
        .accessibilityIdentifier("task-detail-form")
        .safeAreaInset(edge: .top) {
            if let error = store.error {
                Text(error).font(.footnote).padding().frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial)
                    .accessibilityIdentifier("task-action-banner")
            }
        }
        .navigationTitle("Task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if task.status == "recurring", task.attributes["parent"] == nil {
                Button("Edit series metadata") { panel = .series }.disabled(store.isSaving).accessibilityIdentifier("edit-series-metadata")
            }
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
            case .transition: TaskSeriesTransitionEditor(store: store, template: task, onSave: { saved in
                createdSuccessor = saved
                if let retired = store.allTasks.first(where: { $0.id == task.id }) { task = retired }
            })
            case .series: TaskSeriesMetadataEditor(store: store, template: task, onSave: { task = $0 })
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
    case dependency, annotation(TaskAnnotation?), attributes, series, transition

    var id: String {
        switch self {
        case .transition: "transition"
        case .series: "series"
        case .dependency: "dependency"
        case .annotation(let annotation): annotation?.reference.rawValue ?? "new-annotation"
        case .attributes: "attributes"
        }
    }
}
