import SwiftUI
import TskCore

struct TaskSelectionOrganizationControls: View {
    let store: TaskStore
    @State private var isCreatingProject = false
    @State private var isChoosingTag = false
    @State private var projectName = ""

    var body: some View {
        let projectValue = store.selectionChanges.project.map { $0.isEmpty ? "None" : $0 }
        let priorityValue = store.selectionChanges.priority.map(TaskRowParameter.priorityTitle)
        VStack(alignment: .trailing, spacing: 8) {
            Menu {
                ForEach(store.availableProjects.map { UTF8String($0) }) { project in
                    Button(project.rawValue) { store.selectionChanges.project = project.rawValue }
                }
                Button("New project…", systemImage: "folder.badge.plus") {
                    projectName = ""
                    isCreatingProject = true
                }
                Button("Clear project") { store.selectionChanges.project = "" }
                if store.selectionChanges.project != nil {
                    Button("Leave unchanged") { store.selectionChanges.project = nil }
                }
            } label: {
                pill(.project, value: projectValue)
            }
            .selectionControl(.project, value: projectValue)
            Button {
                isChoosingTag = true
            } label: {
                pill(.tags, value: tagValue)
            }
            .selectionControl(.tags, value: tagValue)
            .popover(isPresented: $isChoosingTag, attachmentAnchor: .rect(.bounds)) {
                TaskSelectionTagPicker(store: store)
                    .presentationCompactAdaptation(.popover)
            }
            Menu {
                ForEach(["H", "M", "L"], id: \.self) { priority in
                    Button(TaskRowParameter.priorityTitle(priority)) { store.selectionChanges.priority = priority }
                }
                Button("Clear priority") { store.selectionChanges.priority = "" }
                if store.selectionChanges.priority != nil {
                    Button("Leave unchanged") { store.selectionChanges.priority = nil }
                }
            } label: {
                pill(.priority, value: priorityValue)
            }
            .selectionControl(.priority, value: priorityValue)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isCreatingProject) {
            NavigationStack {
                Form {
                    TextField("Project name", text: $projectName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(stageProject)
                        .accessibilityIdentifier("selection-name")
                }
                .navigationTitle("New project")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { isCreatingProject = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Use project", action: stageProject).disabled(projectName.isEmpty)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func stageProject() {
        guard !projectName.isEmpty else { return }
        store.selectionChanges.project = projectName
        isCreatingProject = false
    }

    private var tagValue: String? {
        switch store.selectionChanges.tag {
        case .add(let name): "Add " + name
        case .remove(let name): "Remove " + name
        case nil: nil
        }
    }

    private func pill(_ parameter: TaskRowParameter, value: String?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: parameter.symbol)
            if let value {
                Text(value).lineLimit(1).truncationMode(.middle)
            }
        }
        .padding(.horizontal, value == nil ? 0 : 16)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
    }
}

private extension View {
    func selectionControl(_ parameter: TaskRowParameter, value: String?) -> some View {
        glassEffect(.regular.tint(value == nil ? .clear : Color.accentColor.opacity(0.15)).interactive(), in: Capsule())
            .accessibilityLabel(parameter.title + " for selected tasks")
            .accessibilityValue(value ?? "Unchanged")
            .accessibilityIdentifier("selection-" + parameter.rawValue)
    }
}

private struct TaskSelectionTagPicker: View {
    let store: TaskStore
    @Environment(\.dismiss) private var dismiss
    @State private var removing: Bool
    @State private var query = ""

    init(store: TaskStore) {
        self.store = store
        if case .remove = store.selectionChanges.tag { _removing = State(initialValue: true) }
        else { _removing = State(initialValue: false) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Tags", systemImage: "tag").font(.headline)
                Spacer()
                if store.selectionChanges.tag != nil {
                    Button("Reset") {
                        store.selectionChanges.tag = nil
                        dismiss()
                    }
                }
                Button("Close tags", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
            }
            Picker("Tag operation", selection: $removing) {
                Text("Add").tag(false)
                Text("Remove").tag(true)
            }
            .pickerStyle(.segmented)
            .onChange(of: removing) { query = "" }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(removing ? "Find a tag" : "Find or create a tag", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(submit)
                    .accessibilityIdentifier("selection-tag-search")
                if canSubmit {
                    Button(action: submit) {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .accessibilityLabel(removing ? "Remove tag" : "Add tag")
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(.quaternary, in: Capsule())

            if !choices.isEmpty {
                ViewThatFits(in: .vertical) {
                    tagButtons.fixedSize(horizontal: false, vertical: true)
                    ScrollView { tagButtons }
                }
                .frame(maxHeight: 160)
            } else if removing {
                Text(query.isEmpty ? "No tags on the selected tasks" : "No matching tags")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .buttonStyle(.plain)
        .padding(16)
        .frame(idealWidth: 290, maxWidth: 290)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var tags: [UTF8String] {
        Set((removing ? store.selectionTasks : store.allTasks).flatMap(\.tags).map { UTF8String($0) }).sorted()
    }

    private var choices: [UTF8String] {
        tags.filter { query.isEmpty || $0.rawValue.localizedCaseInsensitiveContains(query) }
    }

    private var tagButtons: some View {
        TaskRowTagLayout(spacing: 6) {
            ForEach(choices) { tag in
                Button {
                    stage(tag.rawValue)
                } label: {
                    Text(tag.rawValue)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(.quaternary, in: Capsule())
                }
                .accessibilityIdentifier("selection-tag-" + tag.rawValue)
            }
        }
    }

    private var canSubmit: Bool {
        !query.isEmpty && (!removing || tags.contains(UTF8String(query)))
    }

    private func submit() {
        if canSubmit { stage(query) }
    }

    private func stage(_ name: String) {
        store.selectionChanges.tag = removing ? .remove(name) : .add(name)
        dismiss()
    }
}
