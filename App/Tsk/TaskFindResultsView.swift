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

    var body: some View {
        NavigationStack {
            Group {
                if results.tasks.isEmpty {
                    ContentUnavailableView("No matching tasks", systemImage: "magnifyingglass", description: Text("No saved tasks match the supplied filters."))
                        .accessibilityIdentifier("find-results-empty")
                } else {
                    List {
                        Section {
                            ForEach(results.tasks) { task in
                                NavigationLink {
                                    TaskDetailView(store: store, task: task)
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
                            Text("\(results.tasks.count) matching tasks")
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
