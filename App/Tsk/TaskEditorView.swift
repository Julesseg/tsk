import SwiftUI
import TskCore

struct TaskEditorView: View {
    let store: TaskStore
    let original: TaskRecord?
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TaskDraft
    @State private var error: String?
    @FocusState private var isDescriptionFocused: Bool

    init(store: TaskStore, task: TaskRecord? = nil) {
        self.store = store
        original = task
        _draft = State(initialValue: TaskDraft(description: task?.description ?? "", attributes: task?.attributes ?? [:]))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("What needs to be done?", text: $draft.description, axis: .vertical)
                        .accessibilityIdentifier("task-description")
                        .focused($isDescriptionFocused)
                }
                Section {
                    Text("Review your task before saving. Changes are stored locally and available offline.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(.red).accessibilityIdentifier("draft-error")
                    }
                }
            }
            .navigationTitle(original == nil ? "New task" : "Edit task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(store.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            let didSave: Bool
                            if let original {
                                didSave = await store.update(id: original.id, changes: changes) != nil
                            } else {
                                didSave = await store.save(draft)
                            }
                            if didSave { dismiss() } else { error = store.error }
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

    private var changes: [String: String?] {
        guard let original else { return [:] }
        var edited = draft.attributes
        edited["description"] = draft.description
        var patch: [String: String?] = [:]
        for key in Set(edited.keys).union(original.attributes.keys) where edited[key] != original.attributes[key] {
            patch.updateValue(edited[key], forKey: key)
        }
        return patch
    }
}
