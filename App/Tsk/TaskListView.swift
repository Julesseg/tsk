import SwiftUI
import TskCore

struct TaskListView: View {
    let store: TaskStore
    let selection: Binding<UUID?>?
    let calendar: TodayCalendarController
    let edit: (TaskRecord) -> Void

    var body: some View {
        Group {
            if store.customView == nil && store.query == .today {
                ScrollViewReader { proxy in
                    List(selection: selection) {
                        TodayCalendarSection(calendar: calendar)
                        Section {
                            if let error = store.error, store.tasks.isEmpty { Text(error); Button("Retry tasks") { Task { await store.reload() } } }
                            else if store.tasks.isEmpty { Text("Nothing planned or due today").foregroundStyle(.secondary) }
                            ForEach(store.tasks) { task in TaskListRow(task: task, store: store, edit: edit) }
                        }
                        .listSectionSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }.accessibilityIdentifier("task-list")
                        .refreshable { await store.reload(); await calendar.refresh() }
                        .onChange(of: selection?.wrappedValue) { _, id in if let id { proxy.scrollTo(id) } }
                }
            } else if let error = store.error, store.tasks.isEmpty {
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
                            TaskListRow(task: task, store: store, edit: edit)
                        }
                    }
                    .accessibilityIdentifier("task-list")
                    .refreshable { await store.reload() }
                    .onChange(of: selection?.wrappedValue) { _, id in if let id { proxy.scrollTo(id) } }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.horizontal, 0, for: .scrollContent)
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
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if !task.project.isEmpty || task.deadline != nil {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if !task.project.isEmpty {
                        Text(task.project).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    TimelineView(.periodic(from: .now, by: 60)) { _ in
                        TaskPlanningCaption(task: task, today: store.currentDate)
                            .multilineTextAlignment(.trailing)
                    }
                    .layoutPriority(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct TaskListRow: View {
    let task: TaskRecord
    let store: TaskStore
    let edit: (TaskRecord) -> Void
    var rowIdentifier: String?

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            if task.canComplete {
                Button {
                    Task { _ = await store.complete(id: task.id) }
                } label: {
                    Image(systemName: "circle")
                        .font(.title2).foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(store.isSaving)
                .accessibilityLabel("\(task.isOccurrence ? "Complete occurrence" : "Complete task"): \(task.description)")
                .accessibilityIdentifier("complete-task-row-\(task.id.uuidString)")
            }
            NavigationLink(value: task.id) {
                TaskListLabel(task: task, store: store)
            }
            .accessibilityIdentifier(rowIdentifier ?? "task-\(task.id.uuidString)")
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 12))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .tag(task.id)
        .contextMenu {
            TaskActivityButton(task: task, store: store)
            if task.canEdit { Button(task.isOccurrence ? "Edit occurrence" : "Edit", systemImage: "pencil") { edit(task) }.disabled(store.isSaving) }
            if task.canComplete {
                Button(task.isOccurrence ? "Complete occurrence" : "Complete", systemImage: "checkmark") { Task { _ = await store.complete(id: task.id) } }.disabled(store.isSaving)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            TaskActivityButton(task: task, store: store).tint(.orange)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if task.canEdit {
                Button(task.isOccurrence ? "Edit occurrence" : "Edit", systemImage: "pencil") { edit(task) }.disabled(store.isSaving)
            }
        }
    }
}
