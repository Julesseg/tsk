import SwiftUI
import TskCore

struct TaskFindResults: Identifiable {
    let id = UUID()
    let tasks: [TaskRecord]
}

struct TaskFindResultsView: View {
    @Environment(\.dismiss) private var dismiss
    let results: TaskFindResults
    let store: TaskStore

    private var currentTasks: [TaskRecord] {
        results.tasks.compactMap { result in
            store.allTasks.first { $0.id == result.id && $0.status != "deleted" }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if currentTasks.isEmpty {
                    ContentUnavailableView("No matching tasks", systemImage: "magnifyingglass", description: Text("No saved tasks match the supplied filters."))
                        .accessibilityIdentifier("find-results-empty")
                } else {
                    List {
                        Section {
                            ForEach(currentTasks) { task in
                                NavigationLink {
                                    TaskFindResultDestination(store: store, taskID: task.id)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(task.description)
                                        Text([task.project.isEmpty ? nil : task.project, task.status.capitalized].compactMap { $0 }.joined(separator: " · "))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .accessibilityIdentifier("find-task-" + task.id.uuidString)
                            }
                        } header: {
                            Text("\(currentTasks.count) matching tasks")
                        } footer: {
                            Text("Results from this Find request. Your saved views and favorites are unchanged.")
                        }
                    }
                    .accessibilityIdentifier("find-results-list")
                }
            }
            .navigationTitle("Find Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("close-find-results")
                }
            }
        }
    }
}

private struct TaskFindResultDestination: View {
    let store: TaskStore
    let taskID: UUID

    var body: some View {
        if let task = store.allTasks.first(where: { $0.id == taskID && $0.status != "deleted" }) {
            TaskDetailView(store: store, task: task)
        } else {
            ContentUnavailableView("Task unavailable", systemImage: "questionmark.folder")
        }
    }
}
