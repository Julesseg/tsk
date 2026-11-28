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
    @State private var query = ""

    var body: some View {
        let tasks = store.selectionTasks
        let counts = tasks.flatMap(\.tags).reduce(into: [UTF8String: Int]()) { counts, tag in
            counts[UTF8String(tag), default: 0] += 1
        }
        var effective = counts
        switch store.selectionChanges.tag {
        case .add(let name): effective[UTF8String(name)] = tasks.count
        case .remove(let name): effective.removeValue(forKey: UTF8String(name))
        case nil: break
        }
        let catalog = Set(store.allTasks.flatMap(\.tags).map { UTF8String($0) })
        let choices = catalog.filter {
            effective[$0, default: 0] < tasks.count && (query.isEmpty || $0.rawValue.localizedCaseInsensitiveContains(query))
        }.sorted()
        let searchTag = UTF8String(query)
        let canAdd = !query.isEmpty && effective[searchTag, default: 0] < tasks.count
        return VStack(alignment: .leading, spacing: 12) {
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
            if !effective.isEmpty {
                chipList {
                    ForEach(effective.keys.sorted()) { tag in
                        let count = effective[tag, default: 0]
                        TaskPickerTag(name: tag.rawValue, active: true, detail: count < tasks.count ? "\(count)/\(tasks.count)" : nil) {
                            store.selectionChanges.tag = counts[tag] == nil ? nil : .remove(tag.rawValue)
                            dismiss()
                        }
                        .accessibilityHint("Remove from all selected tasks")
                        .accessibilityIdentifier("selection-active-tag-" + tag.rawValue)
                    }
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find or create a tag", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { if canAdd { add(searchTag, counts: counts, taskCount: tasks.count) } }
                    .accessibilityIdentifier("selection-tag-search")
                if canAdd {
                    Button {
                        add(searchTag, counts: counts, taskCount: tasks.count)
                    } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .accessibilityLabel("Add tag")
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(.quaternary, in: Capsule())

            if !choices.isEmpty {
                chipList {
                    ForEach(choices) { tag in
                        TaskPickerTag(name: tag.rawValue, active: false, detail: effective[tag] == nil ? nil : "Add to all") {
                            add(tag, counts: counts, taskCount: tasks.count)
                        }
                        .accessibilityHint("Add to all selected tasks")
                        .accessibilityIdentifier("selection-tag-" + tag.rawValue)
                    }
                }
            }
        }
        .font(.subheadline)
        .buttonStyle(.plain)
        .padding(16)
        .frame(idealWidth: 290, maxWidth: 290)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func chipList<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let chips = TaskRowTagLayout(spacing: 6) { content() }
        return ViewThatFits(in: .vertical) {
            chips.fixedSize(horizontal: false, vertical: true)
            ScrollView { chips }
        }
        .frame(maxHeight: 160)
    }

    private func add(_ tag: UTF8String, counts: [UTF8String: Int], taskCount: Int) {
        store.selectionChanges.tag = counts[tag] == taskCount ? nil : .add(tag.rawValue)
        dismiss()
    }
}
