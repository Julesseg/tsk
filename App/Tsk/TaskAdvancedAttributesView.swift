import SwiftUI
import TskCore

struct TaskAdvancedAttributesSection: View {
    let store: TaskStore
    let task: TaskRecord
    let onSave: (TaskRecord) -> Void
    @State private var isEditing = false
    @State private var error: String?

    var body: some View {
        Section("Advanced attributes") {
            ForEach(store.attributeDefinitions) { definition in
                if let value = task.attributes[definition.name.rawValue] {
                    LabeledContent(definition.label.isEmpty ? definition.name.rawValue : definition.label, value: value)
                }
            }
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            Button("Advanced editor", systemImage: "slider.horizontal.3") { isEditing = true }
                .accessibilityIdentifier("advanced-attributes")
        }
        .sheet(isPresented: $isEditing) { TaskAdvancedAttributesEditor(store: store, task: task, onSave: onSave) }
        .task {
            do { try await store.loadAttributeDefinitions(); error = nil }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct TaskAdvancedAttributesEditor: View {
    let store: TaskStore
    let task: TaskRecord
    let onSave: (TaskRecord) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var edits: TaskAttributePatch = [:]
    @State private var error: String?
    @State private var isDefining = false
    @FocusState private var focusedAttribute: UTF8String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Only changed values are validated. Existing and unregistered fields stay intact when you edit other fields.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if !task.canEdit { Text("This task's values are read only in the current task state.").font(.footnote) }
                    if store.attributeDefinitions.isEmpty { Text("Define an attribute to edit its value here.").foregroundStyle(.secondary) }
                }
                ForEach(store.attributeDefinitions) { definition in
                    Section(definition.label.isEmpty ? definition.name.rawValue : definition.label) {
                        Toggle("Set value", isOn: Binding(get: { value(definition) != nil }, set: { enabled in
                            edits.updateValue(enabled ? initialValue(definition) : nil, forKey: definition.name.rawValue)
                        }))
                        .disabled(!task.canEdit || store.isSaving)
                        .accessibilityIdentifier("uda-enabled-\(definition.name.rawValue)")
                        if let raw = value(definition) {
                            if definition.type == .date {
                                if let date = TaskAttributeValues.date(raw) {
                                    DatePicker("Value", selection: Binding(get: { date }, set: { edits[definition.name.rawValue] = String(Int($0.timeIntervalSince1970)) }), displayedComponents: [.date, .hourAndMinute])
                                        .disabled(!task.canEdit || store.isSaving).accessibilityIdentifier("uda-date-\(definition.name.rawValue)")
                                } else {
                                    Text("Unrecognized value: \(raw)").font(.footnote)
                                    Button("Use current date") { edits[definition.name.rawValue] = String(Int(store.currentDate.timeIntervalSince1970)) }
                                        .disabled(!task.canEdit || store.isSaving)
                                }
                            } else {
                                TextField(definition.type.example, text: Binding(get: { raw }, set: { edits[definition.name.rawValue] = $0 }), axis: .vertical)
                                    .focused($focusedAttribute, equals: definition.name)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .keyboardType(definition.type == .numeric ? .numbersAndPunctuation : .default)
                                    .disabled(!task.canEdit || store.isSaving)
                                    .accessibilityLabel(definition.label.isEmpty ? definition.name.rawValue : definition.label)
                                    .accessibilityIdentifier("uda-value-\(definition.name.rawValue)")
                            }
                        }
                        Text("\(definition.name.rawValue) · \(definition.type.rawValue)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityIdentifier("advanced-attributes-form")
            .safeAreaInset(edge: .top) {
                if let error { Text(error).foregroundStyle(.red).padding().frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial).accessibilityIdentifier("advanced-attributes-error") }
            }
            .safeAreaInset(edge: .bottom) {
                if focusedAttribute != nil { HStack { Spacer(); Button("Done") { focusedAttribute = nil }.accessibilityIdentifier("dismiss-attributes-keyboard") }.padding().background(.regularMaterial) }
            }
            .navigationTitle("Advanced attributes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(store.isSaving) }
                ToolbarItem(placement: .primaryAction) { Button("Definitions") { focusedAttribute = nil; isDefining = true }.accessibilityIdentifier("manage-attribute-definitions") }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        focusedAttribute = nil
                        Task {
                            if let saved = await store.updateUserAttributes(id: task.id, changes: changes) { onSave(saved); dismiss() }
                            else { error = store.error }
                        }
                    }
                    .disabled(!task.canEdit || store.isSaving).accessibilityIdentifier("save-advanced-attributes")
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .sheet(isPresented: $isDefining, onDismiss: { Task { await load() } }) { TaskAttributeDefinitionsView(store: store) }
            .task { await load() }
            .interactiveDismissDisabled(store.isSaving)
            .modifier(TaskWorkspacePanel(store: store))
        }
    }

    private func value(_ definition: TaskAttributeDefinition) -> String? {
        if let change = edits[definition.name.rawValue] { return change }
        return task.attributes[definition.name.rawValue]
    }

    private func initialValue(_ definition: TaskAttributeDefinition) -> String {
        switch definition.type {
        case .string, .uuid: ""
        case .numeric: "0"
        case .date: String(Int(store.currentDate.timeIntervalSince1970))
        case .duration: "PT0S"
        }
    }

    private var changes: TaskAttributePatch {
        var patch = edits
        for (name, value) in edits where value.matchesBytes(task.attributes[name]) { patch.removeValue(forKey: name) }
        return patch
    }

    private func load() async {
        do { try await store.loadAttributeDefinitions(); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
