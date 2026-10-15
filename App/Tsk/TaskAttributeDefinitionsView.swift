import SwiftUI
import TskCore

struct TaskAttributeDefinitionsView: View {
    let store: TaskStore
    @Environment(\.dismiss) private var dismiss
    @State private var editor: AttributeDefinitionRoute?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Definitions stay local. Removing or changing a definition keeps all stored task values.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if store.attributeDefinitions.isEmpty { Text("No local attribute definitions").foregroundStyle(.secondary) }
                ForEach(store.attributeDefinitions) { definition in
                    Button { editor = AttributeDefinitionRoute(definition: definition) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(definition.label.isEmpty ? definition.name.rawValue : definition.label)
                            Text("\(definition.name.rawValue) · \(definition.type.rawValue)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("attribute-definition-\(definition.name.rawValue)")
                    .swipeActions { Button("Remove definition", role: .destructive) { Task { await remove(definition) } } }
                    .contextMenu { Button("Remove definition", systemImage: "trash", role: .destructive) { Task { await remove(definition) } } }
                }
            }
            .accessibilityIdentifier("attribute-definitions-list")
            .safeAreaInset(edge: .top) {
                if let error { Text(error).foregroundStyle(.red).padding().frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial).accessibilityIdentifier("attribute-definitions-error") }
            }
            .navigationTitle("Attribute definitions")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("New definition", systemImage: "plus") { editor = AttributeDefinitionRoute(definition: nil) }
                        .accessibilityIdentifier("new-attribute-definition")
                }
            }
            .sheet(item: $editor) { route in TaskAttributeDefinitionEditor(store: store, original: route.definition) }
            .task { await load() }
            .modifier(TaskWorkspacePanel(store: store))
        }
    }

    private func load() async {
        do { try await store.loadAttributeDefinitions(); error = nil }
        catch { self.error = error.localizedDescription }
    }

    private func remove(_ definition: TaskAttributeDefinition) async {
        do { try await store.manager.deleteAttributeDefinition(name: definition.name.rawValue); await load() }
        catch { self.error = error.localizedDescription }
    }
}

private struct AttributeDefinitionRoute: Identifiable {
    let id = UUID()
    let definition: TaskAttributeDefinition?
}

struct TaskAttributeDefinitionEditor: View {
    let store: TaskStore
    let original: TaskAttributeDefinition?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var label: String
    @State private var type: TaskAttributeType
    @State private var usesValues: Bool
    @State private var valuesText: String
    @State private var error: String?
    @State private var isSaving = false
    @FocusState private var field: DefinitionField?

    init(store: TaskStore, original: TaskAttributeDefinition?) {
        self.store = store
        self.original = original
        _name = State(initialValue: original?.name.rawValue ?? "")
        _label = State(initialValue: original?.label ?? "")
        _type = State(initialValue: original?.type ?? .string)
        _usesValues = State(initialValue: original?.values != nil)
        _valuesText = State(initialValue: original?.values?.joined(separator: "\n") ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Attribute") {
                    TextField("Name", text: $name).focused($field, equals: .name)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .disabled(original != nil || isSaving).accessibilityIdentifier("attribute-definition-name")
                    TextField("Label", text: $label).focused($field, equals: .label)
                        .disabled(isSaving).accessibilityIdentifier("attribute-definition-label")
                    Picker("Type", selection: Binding(get: { type }, set: { value in
                        TaskUIBoundaryDiagnostics.event("attribute-definition.type.setter", details: ["previous": type.rawValue, "selected": value.rawValue])
                        type = value
                    })) {
                        ForEach(TaskAttributeType.allCases, id: \.self) { type in Text(type.title).tag(type) }
                    }
                    .pickerStyle(.menu).disabled(isSaving).accessibilityIdentifier("attribute-definition-type")
                }
                if type == .string {
                    Section("Allowed values") {
                        Toggle("Limit values and set their order", isOn: $usesValues)
                            .disabled(isSaving).accessibilityIdentifier("attribute-values-enabled")
                        if usesValues {
                            TextEditor(text: $valuesText).focused($field, equals: .values)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .frame(minHeight: 100).disabled(isSaving)
                                .accessibilityLabel("Allowed values, highest first")
                                .accessibilityIdentifier("attribute-ordered-values")
                            Text("One value per line, highest first. Include an empty line to position unset values. Spelling and case are exact; commas are not allowed.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Text("Names identify stored task fields. Changing the type validates future edits and leaves existing values untouched.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("attribute-definition-form")
            .safeAreaInset(edge: .top) {
                if let error { Text(error).foregroundStyle(.red).padding().frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial).accessibilityIdentifier("attribute-definition-error") }
            }
            .safeAreaInset(edge: .bottom) {
                if field != nil { HStack { Spacer(); Button("Done") { field = nil }.accessibilityIdentifier("dismiss-definition-keyboard") }.padding().background(.regularMaterial) }
            }
            .navigationTitle(original == nil ? "New attribute" : "Edit definition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { field = nil; Task { await save() } }
                        .disabled(isSaving).accessibilityIdentifier("save-attribute-definition")
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .onAppear { field = original == nil ? .name : .label }
            .interactiveDismissDisabled(isSaving)
            .modifier(TaskWorkspacePanel(store: store))
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await store.manager.saveAttributeDefinition(name: name, label: label, type: type, values: type == .string && usesValues ? valuesText.components(separatedBy: "\n") : nil)
            try await store.loadAttributeDefinitions()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private enum DefinitionField: Hashable { case name, label, values }

extension TaskAttributeType {
    var title: String {
        switch self {
        case .string: "String"
        case .numeric: "Numeric"
        case .date: "Date"
        case .duration: "Duration"
        case .uuid: "UUID"
        }
    }

    var example: String {
        switch self {
        case .string: "Text"
        case .numeric: "-1.25"
        case .date: "Date"
        case .duration: "2h or P1DT30M"
        case .uuid: "UUID or prefix of at least 8 characters"
        }
    }
}
