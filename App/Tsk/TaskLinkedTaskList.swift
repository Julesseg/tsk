import SwiftUI
import TskCore

struct TaskLinkedTaskList: View {
    private struct Destination {
        let task: TaskRecord
        let isLink: Bool
    }

    let taskID: UUID
    private let source: TaskStore
    @State private var store: TaskStore
    @State private var calendar: TodayCalendarController
    @State private var destination: Destination?
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
            finish { destination = Destination(task: task, isLink: false) }
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
            information: { task in finish { destination = Destination(task: task, isLink: false) } },
            reveal: { task in finish { destination = Destination(task: task, isLink: true) } }
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
                if destination.isLink, destination.task.canEdit {
                    TaskLinkedTaskList(source: store, taskID: destination.task.id)
                } else {
                    TaskDetailView(store: store, task: destination.task)
                }
            }
        }
        .task {
            await store.reload()
            if let task = store.allTasks.first(where: { $0.id == taskID }) {
                if task.canEdit { store.expandRow(task) }
                else { destination = Destination(task: task, isLink: false) }
            }
            await store.observeParticipantChanges(reconcileWorkspace: false)
        }
    }

    private func finish(after: (() -> Void)? = nil) {
        guard let editing = store.rowEditing else { after?(); return }
        Task {
            if await editing.saveAndCollapse(in: store, reduceMotion: reduceMotion) { after?() }
        }
    }
}
