import SwiftUI
import TskCore

enum TaskEditorField: Hashable {
    case description, project, tag
}

struct TaskEditorView: View {
    let store: TaskStore
    let original: TaskRecord?
    let onSave: ((TaskRecord) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TaskDraft
    @State private var error: String?
    @State private var tagInput = ""
    @State private var tagError: String?
    @FocusState private var focusedField: TaskEditorField?

    init(store: TaskStore, task: TaskRecord? = nil, onSave: ((TaskRecord) -> Void)? = nil) {
        self.store = store
        original = task
        self.onSave = onSave
        var draft = TaskDraft(description: task?.description ?? "", attributes: task?.attributes ?? [:])
        if task == nil, store.customView == nil, let project = store.projectSelection.projectName { draft.project = project }
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("What needs to be done?", text: $draft.description, axis: .vertical)
                        .accessibilityIdentifier("task-description")
                        .focused($focusedField, equals: .description)
                }
                TaskOrganizationSection(draft: $draft, tagInput: $tagInput, tagError: tagError, focus: $focusedField, addTag: { _ = addTag() })
                TaskPlanningSection(draft: $draft, now: store.currentDate)
                Section {
                    Text("Review your task before saving. Changes are stored locally and available offline.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("task-editor-form")
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if focusedField != nil {
                    HStack {
                        Spacer()
                        Button("Hide keyboard", systemImage: "keyboard.chevron.compact.down") { focusedField = nil }
                            .accessibilityIdentifier("dismiss-editor-keyboard")
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.regularMaterial)
                }
            }
            .safeAreaInset(edge: .top) {
                if let error = error ?? tagError {
                    Text(error)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.regularMaterial)
                        .accessibilityIdentifier("draft-error")
                }
            }
            .onChange(of: UTF8String(tagInput)) { _, _ in tagError = nil }
            .navigationTitle(original == nil ? "New task" : "Edit task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(store.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                    .disabled(store.isSaving)
                    .accessibilityIdentifier("save-task")
                }
            }
            .interactiveDismissDisabled(store.isSaving)
            .onAppear { focusedField = .description }
            .focusedSceneValue(\.taskEditor, store.isSaving ? nil : TaskEditorActions(save: save))
            .modifier(TaskWorkspacePanel(store: store))
        }
    }

    private func save() {
        guard !store.isSaving else { return }
        focusedField = nil
        Task {
            if !tagInput.isEmpty, !addTag() { return }
            let didSave: Bool
            if let original {
                if let saved = await store.update(id: original.id, changes: changes) {
                    onSave?(saved)
                    didSave = true
                } else { didSave = false }
            } else { didSave = await store.save(draft) }
            if didSave { dismiss() } else { error = store.error }
        }
    }

    private func addTag() -> Bool {
        do {
            try draft.addTag(tagInput)
            tagInput = ""
            tagError = nil
            return true
        } catch {
            tagError = error.localizedDescription
            return false
        }
    }

    private var changes: TaskAttributePatch {
        guard let original else { return [:] }
        var edited = draft.attributes
        edited["description"] = draft.description
        return edited.changes(comparedTo: original.attributes)
    }
}
