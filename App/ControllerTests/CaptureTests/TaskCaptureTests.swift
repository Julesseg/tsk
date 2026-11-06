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
    store.query = .upcoming
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
    await store.reload()
    store.selectedTaskIDs = [task.id]
    store.isSelectionGestureActive = true
    store.selectionGestureTasks = []
    store.selectionGestureDays = []
    await store.beginCapture(reduceMotion: true)
    #expect(store.rowEditing?.isCapture == true)
    #expect(!store.isSelectingTasks)
    #expect(!store.isSelectionGestureActive)
    #expect(store.visibleTasks.map(\.description) == ["Existing task"])
}

@MainActor @Test func taskURLPreparationRetainsInvalidCaptureAndSavesItsCorrectedFields() async throws {
    let manager = TaskManager(replica: CaptureReplica())
    let store = TaskStore(manager: manager, directory: FileManager.default.temporaryDirectory)
    await store.beginCapture(reduceMotion: true)
    let editing = try #require(store.rowEditing)
    await editing.setExpanded(true, reduceMotion: true)
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
