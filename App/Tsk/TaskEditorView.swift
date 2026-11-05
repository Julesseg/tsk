import SwiftUI
import TskCore

struct TaskEditorView: View {
    let store: TaskStore
    let original: TaskRecord
    let onSave: ((TaskRecord) -> Void)?
    @Environment(TaskURLController.self) private var automation
    @Environment(\.dismiss) private var dismiss
    @State private var taskActionDraftID = UUID()
    @State private var draft: TaskDraft
    @State private var error: String?
    @State private var tagInput = ""
    @State private var isChoosingPriority = false
    @State private var tagError: String?
    @FocusState private var focusedField: TaskEditorField?

    init(store: TaskStore, task: TaskRecord, onSave: ((TaskRecord) -> Void)? = nil) {
        self.store = store
        original = task
        self.onSave = onSave
        let draft = TaskDraft(description: task.description, attributes: task.attributes)
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
                TaskOrganizationSection(draft: $draft, tagInput: $tagInput, isChoosingPriority: $isChoosingPriority, tagError: tagError, focus: $focusedField, addTag: { _ = addTag() })
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
                        Button("Hide keyboard", systemImage: "keyboard.chevron.compact.down") {
                            TaskUIBoundaryDiagnostics.event("editor.keyboard.dismiss", details: ["focusedField": String(describing: focusedField)])
                            focusedField = nil
                        }
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
            .navigationTitle(original.isOccurrence == true ? "Edit occurrence" : "Edit task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(store.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                    .disabled(store.isSaving || isChoosingPriority)
                    .accessibilityIdentifier("save-task")
                }
            }
            .interactiveDismissDisabled(store.isSaving)
            .onAppear {
                focusedField = .description
                store.presentedTaskPanels.insert(taskActionDraftID)
                store.taskActionDraftCommit = (taskActionDraftID, {
                    let saved = await saveDraft()
                    if saved { dismiss() }
                    return saved
                })
            }
            .onDisappear {
                store.presentedTaskPanels.remove(taskActionDraftID)
                if store.taskActionDraftCommit?.id == taskActionDraftID { store.taskActionDraftCommit = nil }
            }
            .taskKeyboardCommands(store.isSaving || isChoosingPriority ? TaskKeyboardCommand.suspended : TaskEditorActions(save: save).keyboardCommands)

        }
        .modifier(TaskActionMessage(controller: automation))
    }

    private func save() {
        guard !store.isSaving, !isChoosingPriority else { return }
        focusedField = nil
        Task { if await saveDraft() { dismiss() } }
    }

    private func saveDraft() async -> Bool {
        guard !store.isSaving, !isChoosingPriority else {
            error = "Finish choosing the priority before leaving this draft."
            store.error = error
            return false
        }
        if !tagInput.isEmpty, !addTag() { store.error = tagError; return false }
        if let saved = await store.update(id: original.id, changes: changes) { onSave?(saved); return true }
        error = store.error
        return false
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
        var edited = draft.attributes
        edited["description"] = draft.description
        return edited.changes(comparedTo: original.attributes)
    }
}
