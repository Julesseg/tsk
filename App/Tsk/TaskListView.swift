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
                        Section("Tasks · Today") {
                            if let error = store.error, store.tasks.isEmpty { Text(error); Button("Retry tasks") { Task { await store.reload() } } }
                            else if store.tasks.isEmpty { Text("Nothing planned or due today").foregroundStyle(.secondary) }
                            ForEach(store.tasks) { task in TaskListRow(task: task, store: store, edit: edit) }
                        }
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
    var dateRole: TaskDateRole?
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.description)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if !context.isEmpty {
                Text(context).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(textSize.isAccessibilitySize ? nil : 1)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) { status }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 4) { status }
            }
            if dateRole == .planned {
                Label("Planned work", systemImage: "calendar")
                    .font(.caption).foregroundStyle(.secondary)
            }
            TaskPlanningCaption(task: task)
            if task.status != "pending" || task.isRecurring {
                Text(task.recurrenceInspection.map { $0.kind == .template ? "Recurring template" : $0.kind == .occurrence ? task.status == "completed" ? "Completed occurrence" : "Generated occurrence" : "Recurrence data · read only" } ?? task.status.capitalized)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var context: String {
        ([task.project].filter { !$0.isEmpty } + task.tags.prefix(2).map { "#" + $0 } + (task.tags.count > 2 ? ["+\(task.tags.count - 2) tags"] : [])).joined(separator: " · ")
    }

    @ViewBuilder private var status: some View {
        if task.isActive {
            Text("\(Image(systemName: "play.circle.fill")) \(task.status == "pending" ? "Active" : "Saved start marker")")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("task-activity-\(task.id.uuidString)")
        }
        TaskAvailabilityView(task: task, store: store)
    }
}

struct TaskListRow: View {
    let task: TaskRecord
    let store: TaskStore
    let edit: (TaskRecord) -> Void
    var dateRole: TaskDateRole?
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
                TaskListLabel(task: task, store: store, dateRole: dateRole)
            }
            .accessibilityIdentifier(rowIdentifier ?? "task-\(task.id.uuidString)")
        }
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
