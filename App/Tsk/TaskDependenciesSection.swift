import SwiftUI
import TskCore

struct TaskDependenciesSection: View {
    let store: TaskStore
    let task: TaskRecord
    let onSave: (TaskRecord) -> Void
    let select: () -> Void

    var body: some View {
        Section("Dependencies") {
            let links = store.dependencyLinks(for: task)
            if links.isEmpty { Text("No prerequisites").foregroundStyle(.secondary) }
            ForEach(links) { link in
                VStack(alignment: .leading, spacing: 4) {
                    if let target = link.task {
                        NavigationLink {
                            TaskDetailView(store: store, task: target)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(target.description)
                                Text(target.status.capitalized).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("dependency-task-\(target.id.uuidString)")
                    } else {
                        Text(link.reference.isEmpty ? "<empty dependency reference>" : link.reference)
                            .font(.caption).textSelection(.enabled)
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
            if task.canEdit {
                Button("Add dependency", systemImage: "plus") { select() }
                    .disabled(store.isSaving)
                    .accessibilityIdentifier("add-dependency")
            }
        }
    }
}

struct TaskDependencySelection: View {
    let store: TaskStore
    let task: TaskRecord
    let onSave: (TaskRecord) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Select a prerequisite. Its completion will unblock this task while preserving the dependency link.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error { Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("dependency-selection-error") } }
                Section("Tasks") {
                    ForEach(candidates) { candidate in
                        Button {
                            Task {
                                if let saved = await store.addDependency(id: task.id, prerequisiteID: candidate.id) {
                                    onSave(saved)
                                    dismiss()
                                } else { error = store.error }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(candidate.description)
                                Text(candidate.status.capitalized).font(.caption).foregroundStyle(.secondary)
                                Text(candidate.id.uuidString).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .disabled(store.isSaving || task.dependencyReferences.contains(candidate.id.uuidString.lowercased()))
                        .accessibilityIdentifier("dependency-candidate-\(candidate.id.uuidString)")
                    }
                    if candidates.isEmpty { Text("No matching tasks").foregroundStyle(.secondary) }
                }
            }
            .searchable(text: $search, prompt: "Search prerequisites")
            .navigationTitle("Add dependency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(store.isSaving) } }
            .interactiveDismissDisabled(store.isSaving)
            .modifier(TaskWorkspacePanel(store: store))
        }
    }

    private var candidates: [TaskRecord] {
        store.allTasks.filter {
            $0.id != task.id && $0.status != "deleted" && (search.isEmpty || $0.description.localizedCaseInsensitiveContains(search))
        }
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
