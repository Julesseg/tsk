import SwiftUI
import TskCore

struct RecurringTemplatesView: View {
    let store: TaskStore
    @Environment(\.dismiss) private var dismiss
    @State private var isCreating = false
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Text("New occurrences come from your designated recurrence-enabled Taskwarrior client. Synchronize that client, run a report such as list, then synchronize again. Use one generator to avoid duplicate occurrences.")
                    Text("If the generator is offline, existing occurrences remain available but new ones will not arrive.").font(.footnote)
                }
                Section("Templates") {
                    if !store.recurringTemplates.contains(where: { !$0.isRetiredRecurringTemplate }) {
                        Text("No recurring templates").foregroundStyle(.secondary)
                    }
                    ForEach(store.recurringTemplates.filter { !$0.isRetiredRecurringTemplate }) { template in
                        NavigationLink(value: template.id) {
                            VStack(alignment: .leading) {
                                Text(template.description)
                                Text(template.attributes["recur"] ?? "Missing recurrence rule").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("recurring-template-\(template.id.uuidString)")
                    }
                }
                if store.recurringTemplates.contains(where: \.isRetiredRecurringTemplate) {
                    Section("Retired templates") {
                        ForEach(store.recurringTemplates.filter(\.isRetiredRecurringTemplate)) { template in
                            NavigationLink(value: template.id) { VStack(alignment: .leading) { Text(template.description); Text("Retired · view retained history").font(.caption).foregroundStyle(.secondary) } }.accessibilityIdentifier("recurring-template-\(template.id.uuidString)")
                        }
                    }
                }
            }
            .accessibilityIdentifier("recurring-template-list")
            .navigationTitle("Recurring templates")
            .navigationDestination(for: UUID.self) { id in
                if let task = store.allTasks.first(where: { $0.id == id }) { TaskDetailView(store: store, task: task) }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("New template", systemImage: "plus") { isCreating = true }.accessibilityIdentifier("new-recurring-template") }
            }
            .refreshable { await store.reload() }
            .task { await store.reload() }
            .sheet(isPresented: $isCreating) {
                RecurringTemplateEditor(store: store) { path.append($0.id) }
            }
        }
    }
}

private struct RecurringTemplateEditor: View {
    let store: TaskStore
    let onSave: (TaskRecord) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft = TaskDraft()
    @State private var firstDue: Date
    @State private var recurrence = "weekly"
    @State private var tagInput = ""
    @State private var isChoosingPriority = false
    @State private var error: String?
    @FocusState private var focusedField: TaskEditorField?
    @FocusState private var ruleIsFocused: Bool

    init(store: TaskStore, onSave: @escaping (TaskRecord) -> Void) {
        self.store = store
        self.onSave = onSave
        _firstDue = State(initialValue: store.currentDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("What repeats?", text: $draft.description, axis: .vertical)
                        .focused($focusedField, equals: .description).accessibilityIdentifier("recurring-description")
                }
                Section("Recurrence") {
                    DatePicker("First due", selection: $firstDue, displayedComponents: [.date, .hourAndMinute])
                        .accessibilityIdentifier("recurring-first-due")
                    Menu("Choose a frequency") {
                        ForEach(["daily", "weekdays", "weekly", "monthly", "quarterly", "yearly"], id: \.self) { rule in Button(rule.capitalized) { recurrence = rule } }
                    }
                    TextField("Taskwarrior rule", text: $recurrence)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($ruleIsFocused).accessibilityIdentifier("recurring-rule")
                    Text("The first due date anchors the series. Older dates can create many missed occurrences when the generator runs.").font(.footnote)
                    Text("Calendar rules use your generator's time zone. Monthly dates can move after a short month; daily rules can change local time across daylight saving.").font(.footnote)
                }
                TaskOrganizationSection(draft: $draft, tagInput: $tagInput, isChoosingPriority: $isChoosingPriority, tagError: error, focus: $focusedField, addTag: { _ = addTag() })
                Section {
                    Text("tsk saves this template and requests synchronization. Your designated Taskwarrior client creates its occurrences; this app does not generate them.").font(.footnote)
                }
            }
            .accessibilityIdentifier("recurring-editor-form")
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if focusedField != nil || ruleIsFocused {
                    HStack { Spacer(); Button("Hide keyboard", systemImage: "keyboard.chevron.compact.down") { focusedField = nil; ruleIsFocused = false }.accessibilityIdentifier("dismiss-recurring-keyboard") }
                        .padding(.horizontal).padding(.vertical, 8).background(.regularMaterial)
                }
            }
            .safeAreaInset(edge: .top) {
                if let error { Text(error).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading).padding().background(.regularMaterial).accessibilityIdentifier("recurring-error") }
            }
            .navigationTitle("New recurring template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(store.isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard !isChoosingPriority else { return }
                        focusedField = nil
                        ruleIsFocused = false
                        Task {
                            if !tagInput.isEmpty, !addTag() { return }
                            if let saved = await store.createRecurringTemplate(RecurringTaskDraft(task: draft, firstDue: firstDue, recurrence: recurrence)) {
                                onSave(saved)
                                dismiss()
                            } else { error = store.error }
                        }
                    }
                    .disabled(store.isSaving || isChoosingPriority).accessibilityIdentifier("save-recurring-template")
                }
            }
            .interactiveDismissDisabled(store.isSaving)
        }
    }

    private func addTag() -> Bool {
        do { try draft.addTag(tagInput); tagInput = ""; error = nil; return true }
        catch { self.error = error.localizedDescription; return false }
    }
}
