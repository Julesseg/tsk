import SwiftUI
import TskCore

struct TaskLinkedTaskList: View {
    let taskID: UUID
    private let source: TaskStore
    @State private var store: TaskStore
    @State private var calendar: TodayCalendarController
    @State private var destination: TaskRecord?
    @State private var taskActionDraftID = UUID()
    @Environment(TaskURLController.self) private var automation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(source: TaskStore, taskID: UUID) {
        self.taskID = taskID
        self.source = source
        _store = State(initialValue: source.linkedTaskStore())
        _calendar = State(initialValue: TodayCalendarController(manager: source.manager))
    }

    var body: some View {
        TaskListView(store: store, calendar: calendar, edit: { task in
            finish { destination = task }
        })
        .navigationTitle("Linked task")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back", systemImage: "chevron.backward") { finish { dismiss() } }
                    .accessibilityIdentifier("back-from-linked-task")
            }
        }
        .environment(\.taskRowActions, TaskRowActions(
            close: { finish() },
            information: { task in finish { destination = task } }
        ))
        .simultaneousGesture(SpatialTapGesture(coordinateSpace: .global).onEnded { tap in
            guard let editing = store.rowEditing, editing.isExpanded,
                  !editing.bounds.contains(tap.location) else { return }
            finish()
        }, including: store.rowEditing == nil ? .subviews : .all)
        .overlay { TaskRowDismissalOverlay(editing: store.rowEditing, close: { finish() }) }
        .modifier(TaskActionMessage(controller: automation, isActive: store.rowEditing?.parameter == nil && store.presentedTaskPanels.subtracting([taskActionDraftID]).isEmpty))
        .onAppear {
            source.presentedTaskPanels.insert(taskActionDraftID)
            source.taskActionDraftCommit = (taskActionDraftID, { [store] in await store.saveRowForTaskActionNavigation() })
        }
        .onDisappear {
            source.presentedTaskPanels.remove(taskActionDraftID)
            if source.taskActionDraftCommit?.id == taskActionDraftID { source.taskActionDraftCommit = nil }
        }
        .navigationDestination(isPresented: Binding(
            get: { destination != nil },
            set: { if !$0 { destination = nil } }
        )) {
            if let destination {
                TaskDetailView(store: store, task: destination)
            }
        }
        .task {
            await store.reload()
            if let task = store.allTasks.first(where: { $0.id == taskID }) {
                if task.canEdit { store.expandRow(task) }
                else { destination = task }
            }
            await store.observeParticipantChanges()
        }
    }

    private func finish(after: (() -> Void)? = nil) {
        guard let editing = store.rowEditing else { after?(); return }
        Task {
            if await editing.saveAndCollapse(in: store, reduceMotion: reduceMotion) { after?() }
        }
    }
}
