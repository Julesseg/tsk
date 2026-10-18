import SwiftUI
import TskCore

struct TaskSeriesOccurrencesView: View {
    let store: TaskStore
    let template: TaskRecord
    private var children: [TaskRecord] { store.allTasks.filter { UUID(uuidString: $0.attributes["parent"] ?? "") == template.id }.sorted { ($0.deadline ?? .distantPast, $0.id.uuidString) < ($1.deadline ?? .distantPast, $1.id.uuidString) } }
    var body: some View {
        List {
            if template.isRetiredRecurringTemplate { Text("This template is retired. Retained unfinished occurrences can still be edited or completed. Completed records remain unchanged.").accessibilityIdentifier("retired-history-explanation") }
            ForEach(["pending", "completed", "deleted"], id: \.self) { status in
                let records = children.filter { $0.status == status }
                if !records.isEmpty {
                    Section(status == "pending" ? "Unfinished occurrences" : status == "completed" ? "Completed history" : "Deleted occurrences") {
                        ForEach(records) { task in
                            NavigationLink { TaskDetailView(store: store, task: task) } label: { VStack(alignment: .leading) { Text(task.description); if let due = task.deadline { Text(due, format: .dateTime.year().month().day().hour().minute()).font(.caption).foregroundStyle(.secondary) } } }
                                .accessibilityIdentifier("series-history-\(task.id.uuidString)")
                        }
                    }
                }
            }
            if children.isEmpty { Text("No occurrences in this saved dataset.") }
        }
        .accessibilityIdentifier("series-occurrences-list")
        .navigationTitle(template.isRetiredRecurringTemplate ? "Retired series history" : "Series occurrences")
    }
}
