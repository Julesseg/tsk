import SwiftUI
import TskCore

struct TaskSelectionOrganizationControls: View {
    let store: TaskStore
    @State private var input: TaskRowParameter?

    var body: some View {
        HStack(spacing: 4) {
            Menu {
                ForEach(store.availableProjects.map { UTF8String($0) }) { project in
                    Button(project.rawValue) { store.selectionChanges.project = project.rawValue }
                }
                Button("New project…", systemImage: "folder.badge.plus") { input = .project }
                Button("Clear project") { store.selectionChanges.project = "" }
                if store.selectionChanges.project != nil {
                    Button("Leave unchanged") { store.selectionChanges.project = nil }
                }
            } label: {
                pill(.project, value: store.selectionChanges.project.map { $0.isEmpty ? "None" : $0 })
            }
            .accessibilityIdentifier("selection-project")
            Button {
                input = .tags
            } label: {
                pill(.tags, value: tagValue)
            }
            .accessibilityIdentifier("selection-tags")
            Menu {
                ForEach(["H", "M", "L"], id: \.self) { priority in
                    Button(TaskRowParameter.priorityTitle(priority)) { store.selectionChanges.priority = priority }
                }
                Button("Clear priority") { store.selectionChanges.priority = "" }
                if store.selectionChanges.priority != nil {
                    Button("Leave unchanged") { store.selectionChanges.priority = nil }
                }
            } label: {
                pill(.priority, value: store.selectionChanges.priority.map(TaskRowParameter.priorityTitle))
            }
            .accessibilityIdentifier("selection-priority")
        }
        .buttonStyle(.plain)
        .sheet(item: $input) { parameter in
            TaskSelectionOrganizationInput(store: store, parameter: parameter)
                .presentationDetents([.medium, .large])
        }
    }

    private var tagValue: String? {
        switch store.selectionChanges.tag {
        case .add(let name): "Add " + name
        case .remove(let name): "Remove " + name
        case nil: nil
        }
    }

    private func pill(_ parameter: TaskRowParameter, value: String?) -> some View {
        TaskRowParameterLabel(parameter: parameter, value: value)
            .padding(.horizontal, 8)
            .frame(minWidth: 44, minHeight: 44)
            .glassEffect(.regular.tint(value == nil ? .clear : Color.accentColor.opacity(0.15)).interactive(), in: Capsule())
            .accessibilityLabel(parameter.title + " for selected tasks")
            .accessibilityValue(value ?? "Unchanged")
    }
}

private struct TaskSelectionOrganizationInput: View {
    let store: TaskStore
    let parameter: TaskRowParameter
    @State private var name = ""
    @State private var removing = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if parameter == .tags {
                    Picker("Tag operation", selection: $removing) {
                        Text("Add").tag(false)
                        Text("Remove").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                TextField(parameter == .tags ? "Tag name" : "Project name", text: $name)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(stage)
                    .accessibilityIdentifier("selection-name")
                if parameter == .tags {
                    let tags = Set((removing ? store.selectionTasks : store.allTasks).flatMap(\.tags).map { UTF8String($0) }).sorted()
                    if !tags.isEmpty {
                        Section("Existing tags") {
                            TaskRowTagLayout(spacing: 7) {
                                ForEach(tags) { tag in
                                    Button(tag.rawValue) { name = tag.rawValue }
                                        .buttonStyle(.bordered)
                                        .buttonBorderShape(.capsule)
                                        .accessibilityIdentifier("selection-tag-" + tag.rawValue)
                                }
                            }
                        }
                    }
                    if store.selectionChanges.tag != nil {
                        Button("Leave tags unchanged") { store.selectionChanges.tag = nil; dismiss() }
                    }
                }
            }
            .navigationTitle(parameter == .tags ? "Tags" : "New project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(parameter == .project ? "Use project" : removing ? "Remove tag" : "Add tag", action: stage)
                        .disabled(name.isEmpty)
                }
            }
            .onAppear {
                switch store.selectionChanges.tag {
                case .add(let tag) where parameter == .tags: name = tag
                case .remove(let tag) where parameter == .tags: name = tag; removing = true
                default: break
                }
            }
        }
    }

    private func stage() {
        guard !name.isEmpty else { return }
        if parameter == .project { store.selectionChanges.project = name }
        else { store.selectionChanges.tag = removing ? .remove(name) : .add(name) }
        dismiss()
    }
}
