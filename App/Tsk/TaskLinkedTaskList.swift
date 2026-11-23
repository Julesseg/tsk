import SwiftUI

struct TaskLinkedTaskList: View {
    private let source: TaskStore
    @State private var store: TaskStore
    @State private var calendar: TodayCalendarController
    @State private var dayPaging: TaskDayPaging
    @State private var taskActionDraftID = UUID()
    private let workspaceControls: TaskWorkspaceControls?
    private let openPlannerDay: ((Date) -> Void)?
    @Environment(TaskURLController.self) private var automation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(source: TaskStore, taskID: UUID, dayPaging: TaskDayPaging? = nil, workspaceControls: TaskWorkspaceControls? = nil,
         openPlannerDay: ((Date) -> Void)? = nil) {
        self.source = source
        self.workspaceControls = workspaceControls
        self.openPlannerDay = openPlannerDay
        _store = State(initialValue: source.linkedTaskStore(for: taskID))
        _calendar = State(initialValue: TodayCalendarController(manager: source.manager))
        _dayPaging = State(initialValue: dayPaging ?? TaskDayPaging())
    }

    private var showsTaskList: Bool { !store.tasks.isEmpty || (!store.isLoading && store.error != nil) }

    var body: some View {
        Group {
            if showsTaskList {
                TaskListView(store: store, calendar: calendar, dayPaging: dayPaging,
                             workspaceControls: workspaceControls, openPlannerDay: openPlannerDay)
            } else if store.isLoading {
                ProgressView()
            } else {
                ContentUnavailableView("Task unavailable", systemImage: "questionmark.folder")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if !showsTaskList, let workspaceControls {
                GeometryReader { geometry in
                    TaskWorkspaceFooter(store: store, paging: dayPaging, availableWidth: geometry.size.width,
                                        controls: workspaceControls, openPlannerDay: openPlannerDay)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .navigationTitle("Linked task")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back", systemImage: "chevron.backward") { finish { dismiss() } }
                    .accessibilityIdentifier("back-from-linked-task")
            }
        }
        .environment(\.taskRowActions, TaskRowActions(close: { finish() }))
        .simultaneousGesture(SpatialTapGesture(coordinateSpace: .global).onEnded { tap in
            guard let editing = store.rowEditing, editing.isExpanded,
                  editing.viewport.contains(tap.location),
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
        .task {
            await store.reload()
            if let task = store.tasks.first { store.expandRow(task) }
            await store.observeParticipantChanges()
        }
    }

    private func finish(after: (() -> Void)? = nil) {
        guard let editing = store.rowEditing else { after?(); return }
        Task {
            if await editing.saveAndCollapse(in: store, reduceMotion: reduceMotion, includingParameter: after != nil) { after?() }
        }
    }
}
