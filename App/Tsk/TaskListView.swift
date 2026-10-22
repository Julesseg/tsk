import SwiftUI
import TskCore

struct TaskListView: View {
    let store: TaskStore
    let selection: Binding<UUID?>?
    let calendar: TodayCalendarController
    let edit: (TaskRecord) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if store.customView == nil && store.query == .today {
                ScrollViewReader { proxy in
                    List(selection: selection) {
                        TodayCalendarSection(calendar: calendar)
                        Section {
                            if let error = store.error, store.visibleTasks.isEmpty { Text(error); Button("Retry tasks") { Task { await store.reload() } } }
                            else if store.visibleTasks.isEmpty { Text("Nothing planned or due today").foregroundStyle(.secondary) }
                            ForEach(store.visibleTasks) { task in TaskListRow(task: task, store: store, edit: edit) }
                        }
                        .listSectionSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }.accessibilityIdentifier("task-list")
                        .refreshable { await store.reload(); await calendar.refresh() }
                        .onChange(of: selection?.wrappedValue) { _, id in if let id { proxy.scrollTo(id) } }
                }
            } else if let error = store.error, store.visibleTasks.isEmpty {
                ContentUnavailableView {
                    Label("Tasks unavailable", systemImage: "exclamationmark.triangle")
                } description: { Text(error) } actions: {
                    Button("Retry") { Task { await store.reload() } }
                }
            } else if store.visibleTasks.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: "checklist", description: Text(store.customView != nil ? "Edit the filter or choose another view to find tasks." : "Capture a task to get started. Saved tasks stay on this device when you're offline."))
            } else if store.customView == nil && store.query == .upcoming {
                UpcomingTaskList(store: store, selection: selection, edit: edit)
            } else {
                ScrollViewReader { proxy in
                    List(selection: selection) {
                        ForEach(store.visibleTasks) { task in
                            TaskListRow(task: task, store: store, edit: edit)
                        }
                    }
                    .accessibilityIdentifier("task-list")
                    .refreshable { await store.reload() }
                    .onChange(of: selection?.wrappedValue) { _, id in if let id { proxy.scrollTo(id) } }
                }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: store.completionFeedback.removingIDs(context: store.completionContext))
        .environment(\.defaultMinListRowHeight, 0)
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .overlay { if store.isLoading && store.visibleTasks.isEmpty { ProgressView() } }
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
    var isCompleted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.description)
                .font(.subheadline)
                .strikethrough(isCompleted)
                .foregroundStyle(isCompleted ? .secondary : .primary)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var phase: TaskCompletionFeedback.Phase? { store.completionFeedback.phase(for: task.id, context: store.completionContext) }
    private var checked: Bool { phase == .checked || phase == .covering || phase == .collapsing }
    private var visibility: CGFloat { phase == .covering || phase == .collapsing ? 0 : 1 }

    var body: some View {
        HStack(alignment: task.project.isEmpty && task.deadline == nil ? .center : .top, spacing: 4) {
            if task.canComplete {
                Button {
                    Task { _ = await store.completeFromList(id: task.id, animated: !reduceMotion) }
                } label: {
                    Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                        .font(.title2).foregroundStyle(.secondary)
                        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace, options: .speed(3)))
                        .animation(reduceMotion ? nil : .default, value: checked)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(phase != nil)
                .allowsHitTesting(!store.isSaving)
                .accessibilityLabel("\(task.isOccurrence ? "Complete occurrence" : "Complete task"): \(task.description)")
                .accessibilityValue(checked ? "Completed" : phase == .saving ? "Saving" : "Not completed")
                .accessibilityIdentifier("complete-task-row-\(task.id.uuidString)")
            }
            NavigationLink(value: task.id) {
                TaskListLabel(task: task, store: store, isCompleted: checked)
            }
            .disabled(phase != nil)
            .accessibilityIdentifier(rowIdentifier ?? "task-\(task.id.uuidString)")
        }
        .padding(.vertical, 8)
        .fixedSize(horizontal: false, vertical: true)
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .white], startPoint: .top, endPoint: .bottom).frame(height: 6)
                Rectangle().fill(.white)
                LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom).frame(height: 6)
            }
            .padding(.horizontal, -12)
            .scaleEffect(x: 1, y: visibility)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.42), value: visibility)
        .accessibilityHidden(phase == .collapsing)
        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 12))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .tag(task.id)
        .contextMenu {
            TaskActivityButton(task: task, store: store).disabled(phase != nil)
            if task.canEdit { Button(task.isOccurrence ? "Edit occurrence" : "Edit", systemImage: "pencil") { edit(task) }.disabled(store.isSaving || phase != nil) }
            if task.canComplete {
                Button(task.isOccurrence ? "Complete occurrence" : "Complete", systemImage: "checkmark") { Task { _ = await store.completeFromList(id: task.id, animated: !reduceMotion) } }.disabled(store.isSaving || phase != nil)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            TaskActivityButton(task: task, store: store).tint(.orange).disabled(phase != nil)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if task.canEdit {
                Button(task.isOccurrence ? "Edit occurrence" : "Edit", systemImage: "pencil") { edit(task) }.disabled(store.isSaving || phase != nil)
            }
        }
    }
}
