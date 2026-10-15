import SwiftUI
import TskCore

struct RawFilterEditorView: View {
    let store: TaskStore
    let original: SavedTaskView?
    let onOpen: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var expression: String
    @State private var error: String?
    @State private var matches: Int?
    @State private var isWorking = false
    @FocusState private var focusedField: FilterEditorField?

    init(store: TaskStore, original: SavedTaskView?, onOpen: @escaping () -> Void) {
        self.store = store
        self.original = original
        self.onOpen = onOpen
        _name = State(initialValue: original?.name ?? "")
        _expression = State(initialValue: original?.expression ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("View name") {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("custom-view-name")
                        .focused($focusedField, equals: .name)
                        .disabled(isWorking)
                }
                Section("Taskwarrior expression") {
                    TextEditor(text: $expression)
                        .focused($focusedField, equals: .expression)
                        .disabled(isWorking)
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .frame(minHeight: 120)
                        .accessibilityLabel("Taskwarrior filter expression")
                        .accessibilityIdentifier("raw-filter-expression")
                    Text("Example: due:today and +READY\nFor a numeric field: score.above:2\nA blank expression shows all tasks, including completed tasks.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Check results") { focusedField = nil; Task { await preview() } }
                        .disabled(isWorking).accessibilityIdentifier("check-filter")
                    if let matches { Text("\(matches) matching tasks").accessibilityIdentifier("filter-match-count") }
                }
                Section {
                    Button("Open without saving") { focusedField = nil; Task { await apply() } }
                        .disabled(isWorking).accessibilityIdentifier("apply-filter")
                    Text("Saved views stay on this device. Search uses case-sensitive Taskwarrior 3.5 defaults.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("raw-filter-form")
            .safeAreaInset(edge: .bottom) {
                if focusedField != nil {
                    HStack {
                        Spacer()
                        Button("Done") { focusedField = nil }
                            .accessibilityIdentifier("dismiss-filter-keyboard")
                    }
                    .padding().background(.regularMaterial)
                }
            }
            .safeAreaInset(edge: .top) {
                if let error {
                    Text(error).foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding().background(.regularMaterial)
                        .accessibilityIdentifier("filter-error")
                }
            }
            .navigationTitle(original == nil ? "New custom view" : "Edit custom view")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isWorking) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { focusedField = nil; Task { await save() } }
                        .disabled(isWorking).accessibilityIdentifier("save-custom-view")
                }
            }
            .onChange(of: UTF8String(expression)) { _, _ in matches = nil; error = nil }
            .interactiveDismissDisabled(isWorking)
        }
    }

    private func preview() async {
        isWorking = true
        defer { isWorking = false }
        do { matches = try await store.manager.tasks(filter: expression).count; error = nil }
        catch { matches = nil; self.error = error.localizedDescription }
    }

    private func apply() async {
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await store.manager.tasks(filter: expression)
            store.customView = CustomViewSelection(id: nil, name: name.isEmpty ? "Custom filter" : name, expression: expression)
            dismiss(); onOpen()
        } catch { self.error = error.localizedDescription }
    }

    private func save() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let view = try await store.manager.saveView(id: original?.id, name: name, expression: expression)
            try await store.loadSavedViews()
            store.openView(view)
            dismiss(); onOpen()
        } catch { self.error = error.localizedDescription }
    }
}

private enum FilterEditorField: Hashable { case name, expression }
