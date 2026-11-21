import Foundation
import Testing
import TskCore

private actor CaptureReplica: TaskReplica {
    var records: [TaskRecord] = []
    var failCreate = false
    func setFailure(_ failure: Bool) { failCreate = failure }
    func tasks() async throws -> [TaskRecord] { records }
    func create(id: UUID, attributes: TaskAttributes) async throws -> TaskRecord {
        if failCreate { throw TaskManagementError.storage("Capture storage unavailable") }
        let task = TaskRecord(id: id, attributes: attributes)
        records.append(task)
        return task
    }
    func update(id: UUID, changes: TaskAttributePatch) async throws -> TaskRecord {
        let index = records.firstIndex { $0.id == id }!
        for (key, value) in changes { records[index].attributes[key] = value }
        return records[index]
    }
}

@MainActor @Test func repeatedCaptureRetainsOneDraftAndBlankCollapseCreatesNothing() async throws {
    let manager = TaskManager(replica: CaptureReplica())
    let store = TaskStore(manager: manager, directory: FileManager.default.temporaryDirectory)
    await store.beginCapture(reduceMotion: true)
    let editing = try #require(store.rowEditing)
    await editing.setExpanded(true, reduceMotion: true)
    await store.beginCapture(reduceMotion: true)
    #expect(store.rowEditing === editing)
    #expect(await editing.saveAndCollapse(in: store, reduceMotion: true))
    #expect(store.rowEditing == nil)
    #expect(try await manager.tasks().isEmpty)
}

@MainActor @Test func failedCaptureKeepsInputAndRetryCreatesExactlyOneTask() async throws {
    let replica = CaptureReplica()
    let manager = TaskManager(replica: replica)
    let store = TaskStore(manager: manager, directory: FileManager.default.temporaryDirectory)
    store.query = .completed
    await store.beginCapture(reduceMotion: true)
    let editing = try #require(store.rowEditing)
    await editing.setExpanded(true, reduceMotion: true)
    editing.draft.taskDraft.description = "Keep until saved"
    await replica.setFailure(true)
    #expect(!(await editing.saveAndCollapse(in: store, reduceMotion: true)))
    #expect(store.rowEditing === editing)
    #expect(editing.error?.contains("Capture storage unavailable") == true)
    #expect(editing.draft.taskDraft.description == "Keep until saved")
    await replica.setFailure(false)
    #expect(await editing.saveAndCollapse(in: store, reduceMotion: true))
    #expect(!(await editing.saveAndCollapse(in: store, reduceMotion: true)))
    #expect(try await manager.tasks().map(\.description) == ["Keep until saved"])
    #expect(store.tasks.isEmpty)
    #expect(store.captureConfirmation?.description == "Keep until saved")
}

@MainActor @Test func captureFinishesExistingEditsBeforeFreezingTheNewList() async throws {
    let manager = TaskManager(replica: CaptureReplica())
    let original = try await manager.create(TaskDraft(description: "Original"))
    let store = TaskStore(manager: manager, directory: FileManager.default.temporaryDirectory)
    store.selectWorkspaceView(.inbox)
    await store.reload()
    store.expandRow(original)
    let editing = try #require(store.rowEditing)
    await editing.setExpanded(true, reduceMotion: true)
    editing.draft.taskDraft.description = "Revised"
    await store.beginCapture(reduceMotion: true)
    #expect(store.rowEditing?.isCapture == true)
    #expect(store.visibleTasks.map(\.description) == ["Revised"])
    #expect(try await manager.tasks().map(\.description) == ["Revised"])
}

@MainActor @Test func captureCannotReplaceAnInvalidExistingEditorOrItsOpenPicker() async throws {
    let manager = TaskManager(replica: CaptureReplica())
    let original = try await manager.create(TaskDraft(description: "Original"))
    let store = TaskStore(manager: manager, directory: FileManager.default.temporaryDirectory)
    store.selectWorkspaceView(.inbox)
    await store.reload()
    store.expandRow(original)
    let editing = try #require(store.rowEditing)
    await editing.setExpanded(true, reduceMotion: true)
    editing.draft.taskDraft.description = " "
    await store.beginCapture(reduceMotion: true)
    #expect(store.rowEditing === editing)
    #expect(editing.error != nil)
    editing.draft.taskDraft.description = "Revised"
    editing.parameter = .tags
    await store.beginCapture(reduceMotion: true)
    #expect(store.rowEditing === editing)
    #expect(editing.parameter == nil)
    #expect(try await manager.task(id: original.id).description == "Original")
}

@MainActor @Test func captureEndsSelectionBeforeFreezingTheDraftList() async throws {
    let manager = TaskManager(replica: CaptureReplica())
    let task = try await manager.create(TaskDraft(description: "Existing task"))
    let store = TaskStore(manager: manager, directory: FileManager.default.temporaryDirectory)
    store.selectWorkspaceView(.inbox)
    await store.reload()
    store.selectedTaskIDs = [task.id]
    store.isSelectionGestureActive = true
    store.selectionGestureTasks = []
    await store.beginCapture(reduceMotion: true)
    #expect(store.rowEditing?.isCapture == true)
    #expect(!store.isSelectingTasks)
    #expect(!store.isSelectionGestureActive)
    #expect(store.visibleTasks.map(\.description) == ["Existing task"])
}

@MainActor @Test func taskURLPreparationRetainsInvalidCaptureAndSavesItsCorrectedFields() async throws {
    let manager = TaskManager(replica: CaptureReplica())
    let store = TaskStore(manager: manager, directory: FileManager.default.temporaryDirectory)
    let openPanel = UUID()
    store.presentedTaskPanels.insert(openPanel)
    #expect(!(await store.prepareForTaskActionNavigation()))
    store.presentedTaskPanels.remove(openPanel)
    await store.beginCapture(reduceMotion: true)
    let editing = try #require(store.rowEditing)
    await editing.setExpanded(true, reduceMotion: true)
    #expect(!(await store.prepareForTaskActionNavigation()))
    #expect(store.rowEditing === editing)
    #expect(editing.error != nil)
    editing.draft.taskDraft.description = "Capture before URL"
    editing.parameter = .tags
    editing.draft.tagInput = "bad tag"
    #expect(!(await store.prepareForTaskActionNavigation()))
    #expect(store.rowEditing === editing)
    #expect(editing.parameter == .tags)
    #expect(editing.draft.tagInput == "bad tag")
    #expect(try await manager.tasks().isEmpty)
    editing.draft.tagInput = "trip"
    #expect(await store.prepareForTaskActionNavigation())
    #expect(store.rowEditing == nil)
    let saved = try #require(try await manager.tasks().first)
    #expect(saved.description == "Capture before URL")
    #expect(saved.tags == ["trip"])
}

@MainActor @Test func nestedLinkedTaskDraftAndPanelGateRemainVisibleToRootURLNavigation() async throws {
    let manager = TaskManager(replica: CaptureReplica())
    let store = TaskStore(manager: manager, directory: FileManager.default.temporaryDirectory)
    let nested = store.linkedTaskStore().linkedTaskStore()
    let panel = UUID()
    nested.presentedTaskPanels.insert(panel)
    #expect(await store.prepareForTaskActionNavigation() == false)
    var validated = false
    nested.taskActionDraftCommit = (panel, {
        validated = true
        return false
    })
    #expect(await store.prepareForTaskActionNavigation() == false)
    #expect(validated)
    nested.presentedTaskPanels.remove(panel)
    nested.taskActionDraftCommit = nil
    #expect(await store.prepareForTaskActionNavigation())
}

@MainActor @Test func navigationSavesValidDraftAndRestoresOriginalWorkspace() async throws {
    let replica = CaptureReplica()
    let manager = TaskManager(replica: replica)
    let original = try await manager.create(TaskDraft(description: "Original"))
    let store = TaskStore(manager: manager, directory: FileManager.default.temporaryDirectory)
    store.selectWorkspaceView(.today)
    await store.beginCapture(reduceMotion: true)
    let editing = try #require(store.rowEditing)
    await editing.setExpanded(true, reduceMotion: true)
    editing.draft.taskDraft.description = "Saved before navigation"
    #expect(await store.prepareForTaskActionNavigation())
    try await store.openNavigation(manager.navigationDestination(taskID: original.id))
    #expect(store.rowEditing?.draft.original.id == original.id)
    #expect(store.rowEditing?.isExpanded == true)
    #expect(store.query == .unfinished)
    #expect(await store.returnFromNavigation())
    #expect(store.selectedWorkspaceView == .today)
    #expect(store.rowEditing == nil)
    #expect(try await manager.tasks().count == 2)
}

@MainActor @Test func navigationFailureRetainsDraftPickerAndNestedGateUntilSuccessfulSave() async throws {
    let replica = CaptureReplica()
    let manager = TaskManager(replica: replica)
    let root = TaskStore(manager: manager, directory: FileManager.default.temporaryDirectory)
    let nested = root.linkedTaskStore()
    await nested.beginCapture(reduceMotion: true)
    let row = try #require(nested.rowEditing)
    await row.setExpanded(true, reduceMotion: true)
    row.draft.taskDraft.description = "Retained nested draft"
    row.parameter = .tags
    row.draft.tagInput = "two words"
    let panel = UUID()
    nested.presentedTaskPanels.insert(panel)
    nested.taskActionDraftCommit = (panel, { await nested.saveRowForTaskActionNavigation() })
    #expect(!(await root.prepareForTaskActionNavigation()))
    #expect(nested.rowEditing === row)
    #expect(row.parameter == .tags)
    #expect(row.error != nil)
    row.draft.tagInput = "valid"
    await replica.setFailure(true)
    #expect(!(await root.prepareForTaskActionNavigation()))
    #expect(nested.rowEditing === row)
    #expect(row.parameter == .tags)
    #expect(row.error?.contains("Capture storage unavailable") == true)
    #expect(root.navigationReturn == nil)
    await replica.setFailure(false)
    #expect(await root.prepareForTaskActionNavigation())
    #expect(nested.rowEditing == nil)
    #expect(try await manager.tasks().map(\.tags) == [["valid"]])
}

@MainActor @Test func completedOccurrenceExpandsReadOnlyAndClosesWithoutMutation() async throws {
    let replica = CaptureReplica()
    let id = UUID()
    _ = try await replica.create(id: id, attributes: ["description": "Completed occurrence", "status": "completed", "parent": UUID().uuidString, "imask": "0", "due": "2000000000"])
    let manager = TaskManager(replica: replica)
    let store = TaskStore(manager: manager, directory: FileManager.default.temporaryDirectory)
    try await store.openNavigation(manager.navigationDestination(taskID: id))
    let row = try #require(store.rowEditing)
    #expect(row.draft.original.canEdit == false)
    #expect(row.isExpanded)
    #expect(await store.returnFromNavigation())
    #expect(try await manager.task(id: id).description == "Completed occurrence")
    #expect(store.rowEditing == nil)
}

@MainActor @Test func workspaceCaptureDefaultsStaySeparateFromExternalActions() async throws {
    let manager = TaskManager(replica: CaptureReplica())
    let store = TaskStore(manager: manager, directory: FileManager.default.temporaryDirectory)
    let day = try #require(Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())))
    for (view, project, scheduled) in [(WorkspaceView.today, "", Optional(day)), (.projects, "Work", nil), (.inbox, "", nil)] {
        store.selectWorkspaceView(view)
        if view == .today { store.plannerDay = day }
        if view == .projects { store.projectSelection = .project("Work") }
        #expect(store.selectedWorkspaceView == view)
        await store.beginCapture(reduceMotion: true)
        let editing = try #require(store.rowEditing)
        await editing.setExpanded(true, reduceMotion: true)
        #expect(editing.draft.taskDraft.plannedDate == scheduled)
        #expect(editing.draft.taskDraft.project == project)
        #expect(editing.draft.taskDraft.scheduled()?.hasTime != true)
        #expect(await editing.saveAndCollapse(in: store, reduceMotion: true))
        let external = try await manager.addTask(AddTaskInput(description: "External from " + view.title))
        #expect(external.plannedDate == nil && external.project.isEmpty)
        let supplied = try await manager.addTask(AddTaskInput(description: "Explicit from " + view.title, project: "Home", scheduled: day))
        #expect(supplied.plannedDate == day && supplied.project == "Home")
    }
}

@MainActor @Test func calendarSelectionBlocksDaySwipesAndRetainsSelectionWhenSchedulingFails() async throws {
    let manager = TaskManager(replica: CaptureReplica())
    let task = try await manager.create(TaskDraft(description: "Keep selected"))
    let store = TaskStore(manager: manager, directory: FileManager.default.temporaryDirectory)
    store.selectWorkspaceView(.today)
    await store.reload()
    let original = store.displayedDay
    let next = Calendar.current.date(byAdding: .day, value: 1, to: original)!
    store.browseDay(next)
    #expect(store.displayedDay == next)
    store.selectedTaskIDs = [task.id]
    store.moveDay(by: -1)
    #expect(store.displayedDay == next)
    #expect(!(await store.scheduleSelection(on: original)))
    #expect(store.selectedTaskIDs == [task.id])
    #expect(store.isSelectingTasks)
    #expect(store.error != nil)
    #expect(try await manager.task(id: task.id).plannedDate == nil)
    store.endTaskSelection()
    #expect(!store.isSelectingTasks)
}

@MainActor @Test func nativeDraggingAdmitsOnlySelectedMembersAndKeepsSelectionNavigationLocked() async throws {
    let day = Calendar.autoupdatingCurrent.startOfDay(for: Date())
    let first = TaskRecord(id: UUID(), attributes: ["status": "pending", "description": "First", "scheduled": String(Int(day.timeIntervalSince1970))])
    let external = TaskRecord(id: UUID(), attributes: ["status": "pending", "description": "External", "scheduled": String(Int(day.timeIntervalSince1970) + 3600)])
    let second = TaskRecord(id: UUID(), attributes: ["status": "pending", "description": "Second", "scheduled": String(Int(day.timeIntervalSince1970))])
    let history = TaskRecord(id: UUID(), attributes: ["status": "completed", "description": "History", "scheduled": String(Int(day.timeIntervalSince1970))])
    let store = TaskStore(manager: TaskManager(replica: CaptureReplica()), directory: FileManager.default.temporaryDirectory)
    store.query = .today
    store.plannerDay = day
    store.tasks = [first, external, second, history]
    #expect(store.activateSelectionGesture())
    #expect(store.applySelectionGesture(startingAt: first.id, from: [], entering: []))
    #expect(!store.beginTaskDrag(id: first.id))
    store.endSelectionGesture()
    #expect(store.isSelectingTasks)
    store.moveDay(by: 1)
    #expect(store.displayedDay == day)
    store.selectedTaskIDs = [second.id, first.id]
    #expect(!store.beginTaskDrag(id: external.id))
    #expect(!store.beginTaskDrag(id: history.id))
    #expect(store.selectedTaskIDs == [first.id, second.id])
    #expect(store.beginTaskDrag(id: second.id))
    #expect(store.taskDrag?.ids == [first.id, second.id])
    store.taskDrag?.cross(external.id)
    #expect(store.tasks == [first, external, second, history])
    #expect(store.selectedTaskIDs == [first.id, second.id])
    store.moveDay(by: 1)
    #expect(store.displayedDay == day)
    store.taskDrag = nil
    store.endTaskSelection()
    #expect(!store.beginTaskDrag(id: history.id))
    #expect(store.beginTaskDrag(id: first.id))
    #expect(store.taskDrag?.ids == [first.id])
}

@MainActor @Test func browsingWithAPrefetchedPagePublishesItsRowsWithItsDate() async throws {
    let day = Calendar.autoupdatingCurrent.startOfDay(for: Date())
    let next = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: day)!
    let manager = TaskManager(replica: CaptureReplica())
    let today = try await manager.create(TaskDraft(description: "Today", attributes: ["scheduled": String(Int(day.timeIntervalSince1970))]))
    let tomorrow = try await manager.create(TaskDraft(description: "Tomorrow", attributes: ["scheduled": String(Int(next.timeIntervalSince1970))]))
    let store = TaskStore(manager: manager, directory: FileManager.default.temporaryDirectory)
    store.selectWorkspaceView(.today)
    await store.reload()
    #expect(store.visibleTasks.contains(where: { $0.id == today.id }))
    let cachedTasks = try await manager.dayPage(on: next)
    store.browseDay(next, cachedTasks: cachedTasks)
    #expect(store.displayedDay == next)
    #expect(store.visibleTasks.map(\.id) == [tomorrow.id])
    store.browseDay(day)
    #expect(store.visibleTasks.isEmpty)
}
