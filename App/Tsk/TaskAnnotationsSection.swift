import SwiftUI
import TskCore

struct TaskAnnotationsSection: View {
    let store: TaskStore
    let task: TaskRecord
    let edit: (TaskAnnotation?) -> Void

    var body: some View {
        Section("Annotations") {
            if task.annotations.isEmpty { Text("No annotations").foregroundStyle(.secondary) }
            ForEach(task.annotations) { annotation in
                VStack(alignment: .leading, spacing: 8) {
                    if let entry = annotation.entry {
                        Text(entry, format: .dateTime.year().month().day().hour().minute().second())
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Unrecognized timestamp: \(annotation.reference.rawValue)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(annotation.text).textSelection(.enabled)
                        .accessibilityIdentifier("annotation-text-\(annotation.reference.rawValue)")
                    if task.canEdit {
                        Button("Edit annotation", systemImage: "pencil") { edit(annotation) }
                            .buttonStyle(.borderless).disabled(store.isSaving)
                            .accessibilityIdentifier("edit-\(annotation.reference.rawValue)")
                    }
                }
                .padding(.vertical, 4)
            }
            if task.canEdit {
                Button("Add annotation", systemImage: "plus.bubble") { edit(nil) }
                    .disabled(store.isSaving).accessibilityIdentifier("add-annotation")
            }
        }
    }
}

struct TaskAnnotationEditor: View {
    let store: TaskStore
    let task: TaskRecord
    let original: TaskAnnotation?
    let onSave: (TaskRecord) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var error: String?
    @FocusState private var isTyping: Bool

    init(store: TaskStore, task: TaskRecord, original: TaskAnnotation?, onSave: @escaping (TaskRecord) -> Void) {
        self.store = store
        self.task = task
        self.original = original
        self.onSave = onSave
        _text = State(initialValue: original?.text ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Annotation") {
                    TextEditor(text: $text)
                        .frame(minHeight: 180)
                        .focused($isTyping)
                        .accessibilityLabel("Annotation text")
                        .accessibilityIdentifier("annotation-editor-text")
                        .disabled(store.isSaving)
                }
                if let original {
                    Section("Original timestamp") {
                        if let entry = original.entry { Text(entry, format: .dateTime.year().month().day().hour().minute().second()) }
                        else { Text(original.reference.rawValue).font(.caption.monospaced()) }
                        Text("Editing keeps this annotation's original timestamp.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityIdentifier("annotation-editor-content")
            .safeAreaInset(edge: .top) {
                if let error {
                    Text(error).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
                        .padding().background(.regularMaterial).accessibilityIdentifier("annotation-editor-error")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isTyping {
                    HStack {
                        Spacer()
                        Button("Done") { isTyping = false }.accessibilityIdentifier("dismiss-annotation-keyboard")
                    }
                    .padding().background(.regularMaterial)
                }
            }
            .navigationTitle(original == nil ? "Add annotation" : "Edit annotation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(store.isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                    .disabled(store.isSaving).accessibilityIdentifier("save-annotation")
                }
            }
            .interactiveDismissDisabled(store.isSaving)
            .onChange(of: UTF8String(text)) { _, _ in error = nil }
            .onAppear { isTyping = true }
            .focusedSceneValue(\.taskEditor, store.isSaving ? nil : TaskEditorActions(save: save))
            .modifier(TaskWorkspacePanel(store: store))
        }
    }
    private func save() {
        guard !store.isSaving else { return }
        isTyping = false
        Task {
            let saved: TaskRecord?
            if let original { saved = await store.editAnnotation(id: task.id, reference: original.reference.rawValue, text: text) }
            else { saved = await store.addAnnotation(id: task.id, text: text) }
            if let saved { onSave(saved); dismiss() }
            else { error = store.error }
        }
    }

}
