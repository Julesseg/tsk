import SwiftUI
import TskCore

struct TaskDependenciesSection: View {
    let store: TaskStore
    let task: TaskRecord
    let onSave: (TaskRecord) -> Void
    let select: () -> Void
    var reveal: ((TaskRecord) -> Void)? = nil

    var body: some View {
        let links = store.dependencyLinks(for: task)
        if links.isEmpty {
            addButton
        } else {
            Section("Dependencies") {
                ForEach(links) { link in
                    VStack(alignment: .leading, spacing: 4) {
                        if let target = link.task {
                            Group {
                                if let reveal {
                                    Button { reveal(target) } label: { prerequisite(target) }
                                } else {
                                    NavigationLink { TaskDetailView(store: store, task: target) } label: { prerequisite(target) }
                                }
                            }
                            .accessibilityIdentifier("dependency-task-\(target.id.uuidString)")
                        } else {
                            Text("Prerequisite unavailable").font(.caption)
                        }
                        if let issue = link.issue {
                            Text(issue.message).font(.caption).foregroundStyle(.secondary)
                        }
                        if task.canEdit {
                            Button("Remove dependency", role: .destructive) {
                                Task {
                                    if let saved = await store.removeDependency(id: task.id, reference: link.reference) { onSave(saved) }
                                }
                            }
                            .buttonStyle(.borderless)
                            .disabled(store.isSaving)
                            .accessibilityIdentifier("remove-dependency-\(link.id.base64EncodedString())")
                        }
                    }
                }
                addButton
            }
        }
    }

    private func prerequisite(_ task: TaskRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.description)
            Text(task.status.capitalized).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var addButton: some View {
        if task.canEdit {
            Button("Add dependency", systemImage: "plus") { select() }
                .disabled(store.isSaving)
                .accessibilityIdentifier("add-dependency")
        }
    }
}

struct TaskDependencySelection: View {
    let store: TaskStore
    let onSave: (TaskRecord) -> Void
    var reveal: ((TaskRecord) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var task: TaskRecord
    @State private var search = ""
    @State private var error: String?

    init(store: TaskStore, task: TaskRecord, onSave: @escaping (TaskRecord) -> Void, reveal: ((TaskRecord) -> Void)? = nil) {
        self.store = store
        self.onSave = onSave
        self.reveal = reveal
        _task = State(initialValue: task)
    }

    var body: some View {
        let options = TaskDependencyOptions(task: task, tasks: store.allTasks, search: search)
        NavigationStack {
            List {
                if let error { Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("dependency-selection-error") } }
                Section("Dependencies") {
                    ForEach(options.links) { link in
                        HStack {
                            if let target = link.task {
                                Group {
                                    if let reveal {
                                        Button { reveal(target) } label: { taskLabel(target) }
                                    } else {
                                        NavigationLink { TaskDetailView(store: store, task: target) } label: { taskLabel(target) }
                                    }
                                }
                                .buttonStyle(.borderless)
                                .accessibilityIdentifier("dependency-task-\(target.id.uuidString)")
                            } else {
                                Text("Prerequisite unavailable")
                            }
                            Spacer()
                            if task.canEdit {
                                Button("Remove dependency", systemImage: "minus.circle", role: .destructive) {
                                    Task { saved(await store.removeDependency(id: task.id, reference: link.reference)) }
                                }
                                .labelStyle(.iconOnly).buttonStyle(.borderless)
                                .accessibilityIdentifier("remove-dependency-\(link.id.base64EncodedString())")
                            }
                        }
                        .disabled(store.isSaving)
                        if let issue = link.issue { Text(issue.message).font(.caption).foregroundStyle(.secondary) }
                    }
                    if options.links.isEmpty { Text("No dependencies").foregroundStyle(.secondary) }
                }
                if task.canEdit {
                    Section("Add dependencies") {
                        ForEach(options.candidates) { candidate in
                            Button {
                                Task { saved(await store.addDependency(id: task.id, prerequisiteID: candidate.id)) }
                            } label: {
                                HStack { taskLabel(candidate); Spacer(); Image(systemName: "plus.circle") }
                            }
                            .disabled(store.isSaving)
                            .accessibilityIdentifier("dependency-candidate-\(candidate.id.uuidString)")
                        }
                        if options.candidates.isEmpty { Text("No matching tasks").foregroundStyle(.secondary) }
                    }
                }
            }
            .accessibilityIdentifier("dependency-selection-list")
            .searchable(text: $search, prompt: "Search prerequisites")
            .navigationTitle("Dependencies")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.disabled(store.isSaving).accessibilityIdentifier("close-dependencies")
                }
            }
            .interactiveDismissDisabled(store.isSaving)
            .modifier(TaskWorkspacePanel(store: store))
        }
    }

    private func taskLabel(_ task: TaskRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.description)
            Text(task.status.capitalized).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func saved(_ record: TaskRecord?) {
        if let record { task = record; error = nil; onSave(record) }
        else { error = store.error }
    }
}

extension TaskDependencyIssue {
    var message: String {
        switch self {
        case .invalidReference: "Invalid dependency reference"
        case .missingReference: "Missing prerequisite; this reference does not block the task"
        case .selfReference: "Existing self dependency; remove it to repair the link"
        case .cycle: "Existing dependency cycle; remove a link to repair it"
        }
    }
}
