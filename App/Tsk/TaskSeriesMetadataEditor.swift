import SwiftUI
import TskCore

struct TaskSeriesMetadataEditor: View {
    let store: TaskStore
    let template: TaskRecord
    let onSave: (TaskRecord) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TaskDraft
    @State private var annotation = ""
    @State private var tagInput = ""
    @State private var tagError: String?
    @State private var error: String?
    @State private var preview: TaskSeriesMetadataPreview?
    @State private var isPreviewing = false
    @FocusState private var field: TaskEditorField?
    @FocusState private var textField: UTF8String?

    init(store: TaskStore, template: TaskRecord, onSave: @escaping (TaskRecord) -> Void) {
        self.store = store
        self.template = template
        self.onSave = onSave
        _draft = State(initialValue: TaskDraft(description: template.description, attributes: template.attributes))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Change the template and preview which future unfinished occurrences will receive only these metadata changes. Completed history and overdue occurrences stay unchanged.")
                    Text("Frequency, dates, links and recurrence bookkeeping are preserved. For one occurrence, use Edit occurrence instead.").font(.footnote).foregroundStyle(.secondary)
                }
                Group {
                    Section("Description") {
                        TextField("What repeats?", text: $draft.description, axis: .vertical)
                            .focused($field, equals: .description).accessibilityIdentifier("series-description")
                    }
                    TaskOrganizationSection(draft: $draft, tagInput: $tagInput, tagError: tagError, focus: $field, addTag: addTag)
                    Section("Series annotations") {
                        ForEach(template.annotations) { note in
                            TextField("Annotation", text: Binding(get: { draft.attributes[note.reference.rawValue] ?? "" }, set: { draft.attributes[note.reference.rawValue] = $0 }), axis: .vertical)
                                .focused($textField, equals: note.reference)
                                .accessibilityIdentifier("series-\(note.reference.rawValue)")
                            if let date = note.entry { Text(date, format: .dateTime.year().month().day().hour().minute().second()).font(.caption).foregroundStyle(.secondary) }
                        }
                        TextField("Add a series annotation", text: $annotation, axis: .vertical)
                            .focused($textField, equals: UTF8String("new-note")).accessibilityIdentifier("series-new-annotation")
                        Text("Only edited annotations and the new note propagate. Other occurrence notes remain intact.").font(.footnote)
                    }
                    ForEach(store.attributeDefinitions) { definition in
                        attribute(definition)
                    }
                }
                .disabled(preview != nil || store.isSaving || isPreviewing)
                if let preview { previewSection(preview) }
            }
            .accessibilityIdentifier("series-metadata-form")
            .navigationTitle("Edit series metadata")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) {
                if let error { Text(error).foregroundStyle(.red).padding().frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial).accessibilityIdentifier("series-metadata-error") }
            }
            .safeAreaInset(edge: .bottom) {
                if field != nil || textField != nil {
                    HStack { Spacer(); Button("Done") { endTyping() }.accessibilityIdentifier("dismiss-series-keyboard") }.padding().background(.regularMaterial)
                        .accessibilityElement(children: .contain).accessibilityIdentifier("series-keyboard-dismissal")
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(store.isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    if let preview {
                        Button("Save series changes") { save(preview) }.disabled(store.isSaving || preview.updates.allSatisfy { $0.changes.isEmpty }).accessibilityIdentifier("save-series-metadata")
                    } else {
                        Button("Preview changes", action: buildPreview).disabled(store.isSaving || isPreviewing).accessibilityIdentifier("preview-series-metadata")
                    }
                }
            }
            .taskKeyboardCommands(editorActions?.keyboardCommands ?? TaskKeyboardCommand.suspended)
            .interactiveDismissDisabled(store.isSaving)
            .task { do { try await store.loadAttributeDefinitions() } catch { self.error = error.localizedDescription } }
            .modifier(TaskWorkspacePanel(store: store))
        }
    }

    @ViewBuilder private func attribute(_ definition: TaskAttributeDefinition) -> some View {
        let name = definition.name.rawValue
        Section(definition.label.isEmpty ? name : definition.label) {
            Toggle("Set value", isOn: Binding(get: { draft.attributes[name] != nil }, set: { draft.attributes[name] = $0 ? initialValue(definition) : nil }))
                .accessibilityIdentifier("series-uda-enabled-\(name)")
            if let value = draft.attributes[name] {
                if definition.type == .string, let values = definition.values {
                    Picker("Value", selection: Binding(get: { UTF8String(value) }, set: { draft.attributes[name] = $0.rawValue })) {
                        if !values.contains(where: { $0.matchesBytes(value) }) { Text("Unrecognized: \(value)").tag(UTF8String(value)) }
                        ForEach(values.map { UTF8String($0) }) { value in Text(value.rawValue.isEmpty ? "Unset" : value.rawValue).tag(value) }
                    }
                    .accessibilityIdentifier("series-uda-value-\(name)")
                } else {
                    TextField(definition.type.example, text: Binding(get: { value }, set: { draft.attributes[name] = $0 }), axis: .vertical)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().focused($textField, equals: definition.name)
                        .accessibilityIdentifier("series-uda-value-\(name)")
                }
                Text(definition.type.rawValue).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func previewSection(_ preview: TaskSeriesMetadataPreview) -> some View {
        Section("Review series changes") {
            Text("\(preview.affected.count) future unfinished occurrences").accessibilityIdentifier("series-preview-count")
            Text("Due on or after \(preview.cutoff.formatted(date: .abbreviated, time: .standard)). Completed history and overdue occurrences are excluded.").font(.footnote)
            if preview.updates.allSatisfy({ $0.changes.isEmpty }) { Text("No metadata changes to save.") }
            Text("Template: \(preview.template.description)")
            if let update = preview.updates.first { changesSummary(update.changes, original: preview.template) }
            ForEach(preview.affected) { task in
                VStack(alignment: .leading, spacing: 6) {
                    Text(task.description)
                    if let due = task.deadline { Text(due, format: .dateTime.year().month().day().hour().minute()).font(.caption) }
                    if let update = preview.updates.first(where: { $0.id == task.id }) { changesSummary(update.changes, original: task) }
                }
                .accessibilityIdentifier("series-preview-\(task.id.uuidString)")
            }
            if preview.affected.isEmpty { Text("The template changes apply to later externally generated occurrences. No existing occurrences will change.") }
            Button("Back to editing") { self.preview = nil; error = nil }.accessibilityIdentifier("edit-series-preview")
            if error != nil { Button("Preview again", action: buildPreview).accessibilityIdentifier("refresh-series-preview") }
        }
    }

    @ViewBuilder private func changesSummary(_ patch: TaskAttributePatch, original: TaskRecord) -> some View {
        ForEach(patch.keyIdentities.filter { $0.rawValue != "modified" }) { key in
            Text(summary(key.rawValue, patch: patch, original: original))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func initialValue(_ definition: TaskAttributeDefinition) -> String {
        switch definition.type {
        case .string: definition.values?.first ?? ""
        case .numeric: "0"
        case .duration: "PT0S"
        case .date: String(Int(store.currentDate.timeIntervalSince1970))
        case .uuid: ""
        }
    }

    private func summary(_ name: String, patch: TaskAttributePatch, original: TaskRecord) -> String {
        let value = patch[name] ?? nil
        if name.utf8.starts(with: "tag_".utf8) { return "\(value == nil ? "Remove" : "Add") tag “\(String(name.dropFirst(4)))”" }
        let label: String
        if name.utf8.starts(with: "annotation_".utf8) { label = "Annotation" }
        else if let definition = store.attributeDefinitions.first(where: { $0.name == UTF8String(name) }) { label = definition.label.isEmpty ? name : definition.label }
        else { label = name.capitalized }
        return "\(label): \(original.attributes[name] ?? "Unset") → \(value ?? "Unset")"
    }

    private var changes: TaskAttributePatch {
        var patch: TaskAttributePatch = [:]
        if !draft.description.matchesBytes(template.description) { patch["description"] = draft.description }
        let names = Set(draft.attributes.keyIdentities + template.attributes.keyIdentities)
        for identity in names {
            let key = identity.rawValue
            if !draft.attributes[key].matchesBytes(template.attributes[key]) { patch.updateValue(draft.attributes[key], forKey: key) }
        }
        return patch
    }

    private func addTag() {
        do { try draft.addTag(tagInput); tagInput = ""; tagError = nil }
        catch { tagError = error.localizedDescription }
    }

    private var editorActions: TaskEditorActions? {
        guard !store.isSaving, !isPreviewing else { return nil }
        if let preview {
            guard preview.updates.contains(where: { !$0.changes.isEmpty }) else { return nil }
            return TaskEditorActions(save: { save(preview) })
        }
        return TaskEditorActions(save: buildPreview)
    }

    private func endTyping() { field = nil; textField = nil }

    private func buildPreview() {
        guard !isPreviewing else { return }
        endTyping()
        if !tagInput.isEmpty { addTag(); if tagError != nil { return } }
        isPreviewing = true
        Task {
            defer { isPreviewing = false }
            do { preview = try await store.manager.previewSeriesMetadata(id: template.id, changes: changes, addingAnnotation: annotation); error = nil }
            catch { self.error = error.localizedDescription }
        }
    }

    private func save(_ preview: TaskSeriesMetadataPreview) {
        endTyping()
        Task {
            if let saved = await store.perform({ try await $0.applySeriesMetadata(preview) }) { onSave(saved); dismiss() }
            else { error = store.error }
        }
    }
}
