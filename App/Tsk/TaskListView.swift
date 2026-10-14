import SwiftUI
import TskCore

struct TaskListView: View {
    let store: TaskStore
    let selection: Binding<UUID?>?
    let edit: (TaskRecord) -> Void

    var body: some View {
        Group {
            if let error = store.error, store.tasks.isEmpty {
                ContentUnavailableView {
                    Label("Tasks unavailable", systemImage: "exclamationmark.triangle")
                } description: { Text(error) } actions: {
                    Button("Retry") { Task { await store.reload() } }
                }
            } else if store.tasks.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: "checklist", description: Text(store.customView != nil ? "Edit the filter or choose another view to find tasks." : "Capture a task to get started. Saved tasks stay on this device when you're offline."))
            } else if store.customView == nil && store.query == .upcoming {
                UpcomingTaskList(store: store, selection: selection, edit: edit)
            } else {
                ScrollViewReader { proxy in
                    List(selection: selection) {
                        ForEach(store.tasks) { task in
                            NavigationLink(value: task.id) {
                                TaskListLabel(task: task, store: store)
                            }
                            .tag(task.id)
                            .accessibilityIdentifier("task-\(task.id.uuidString)")
                            .contextMenu {
                                if task.canEdit { Button("Edit", systemImage: "pencil") { edit(task) }.disabled(store.isSaving) }
                                if task.canComplete {
                                    Button("Complete", systemImage: "checkmark") { Task { _ = await store.complete(id: task.id) } }.disabled(store.isSaving)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if task.canComplete {
                                    Button("Complete", systemImage: "checkmark") { Task { _ = await store.complete(id: task.id) } }
                                        .tint(.green).disabled(store.isSaving)
                                }
                                if task.canEdit {
                                    Button("Edit", systemImage: "pencil") { edit(task) }.disabled(store.isSaving)
                                }
                            }
                        }
                    }
                    .accessibilityIdentifier("task-list")
                    .refreshable { await store.reload() }
                    .onChange(of: selection?.wrappedValue) { _, id in if let id { proxy.scrollTo(id) } }
                }
            }
        }
        .overlay { if store.isLoading && store.tasks.isEmpty { ProgressView() } }
    }

    private var emptyTitle: String {
        if store.customView != nil { return "No matching tasks" }
        switch store.query {
        case .upcoming: return "No upcoming plans or deadlines"
        case .today: return "Nothing planned or due today"
        case .completed: return "No completed tasks"
        default: return "No unfinished tasks"
        }
    }
}

struct TaskListLabel: View {
    let task: TaskRecord
    let store: TaskStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.description)
            if !task.project.isEmpty { Text(task.project).font(.caption).foregroundStyle(.secondary) }
            TaskPlanningCaption(task: task)
            TaskAvailabilityView(task: task, store: store)
            if task.status != "pending" || task.isRecurring {
                Text(task.recurrenceInspection.map { $0.kind == .template ? "Recurring template" : $0.kind == .occurrence ? "Generated occurrence · read only" : "Recurrence data · read only" } ?? task.status.capitalized)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
