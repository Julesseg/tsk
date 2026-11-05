import Foundation
import Observation
import SwiftUI
import TskCore
import UIKit

@MainActor @Observable
final class TaskURLController {
    struct Destination: Identifiable {
        let id = UUID()
        let taskID: UUID
        let store: TaskStore
    }

    var destination: Destination?
    var message: String?
    private var requests: [URL] = []
    private var isExecuting = false

    func receive(_ url: URL, store: TaskStore?) async {
        requests.append(url)
        if let store { await executePending(in: store) }
    }

    func executePending(in store: TaskStore) async {
        guard !isExecuting else { return }
        isExecuting = true
        defer { isExecuting = false }
        while !requests.isEmpty {
            let url = requests.removeFirst()
            message = nil
            var callbacks: TaskActionCallbacks?
            var saved: TaskRecord?
            do {
                callbacks = try TaskActionCallbacks(url: url)
                let action = try TaskActionURL(url: url)
                let active = destination?.store ?? store
                guard await active.prepareForTaskActionNavigation() else {
                    throw TaskActionError.navigationFailed(active.error ?? "Finish the current editing panel before opening a task URL.")
                }
                let task: TaskRecord
                switch action {
                case .add(let input):
                    task = try await store.manager.addTask(input)
                    saved = task
                case .openTask(let id): task = try await store.manager.task(id: id)
                }
                if let callback = try callbacks?.successURL(for: task) {
                    await deliver(callback, saved: saved)
                } else {
                    let containing = TaskStore(manager: store.manager, directory: store.directory)
                    containing.query = task.status == "completed" ? .completed : .all
                    await containing.reload()
                    if let error = containing.error { throw TaskManagementError.storage(error) }
                    destination = Destination(taskID: task.id, store: containing)
                }
                await store.reload()
            } catch {
                let code = TaskActionFailureCode(error: error, savedLocally: saved != nil).rawValue
                message = (saved.map { "Task saved locally (\($0.id.uuidString)). " } ?? "") + error.localizedDescription
                do {
                    if let callback = try callbacks?.errorURL(code: code, message: error.localizedDescription, savedTaskID: saved?.id) {
                        await deliver(callback, saved: saved)
                    }
                } catch {
                    message = (saved != nil ? "Task saved locally. " : "") + "The error callback could not be encoded: " + error.localizedDescription
                }
            }
        }
    }

    func storageUnavailable(_ failure: any Error) async {
        guard !isExecuting else { return }
        isExecuting = true
        defer { isExecuting = false }
        while !requests.isEmpty {
            let url = requests.removeFirst()
            message = failure.localizedDescription
            do {
                let callbacks = try TaskActionCallbacks(url: url)
                if let callback = try callbacks.errorURL(code: TaskActionFailureCode.storageError.rawValue, message: failure.localizedDescription) {
                    await deliver(callback, saved: nil)
                }
            } catch { message = error.localizedDescription }
        }
    }

    private func deliver(_ url: URL, saved: TaskRecord?) async {
        let accepted = await UIApplication.shared.open(url)
        if accepted { message = nil }
        else if let saved {
            message = "Task saved locally (\(saved.id.uuidString)), but the callback could not be delivered. The task was not undone. Opening Add again creates another task."
        } else { message = "The callback could not be delivered. " + (message ?? "") }
    }
}

struct TaskURLDestination: View {
    let destination: TaskURLController.Destination
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var detailID: UUID?
    private var store: TaskStore { destination.store }

    var body: some View {
        NavigationStack {
            TaskListView(store: store, calendar: TodayCalendarController(manager: store.manager), edit: { detailID = $0.id })
                .simultaneousGesture(SpatialTapGesture(coordinateSpace: .global).onEnded { tap in
                    guard let editing = store.rowEditing, editing.isExpanded, !editing.bounds.contains(tap.location) else { return }
                    closeRow()
                }, including: store.rowEditing == nil ? .subviews : .all)
                .navigationTitle("Saved tasks")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Back") {
                            Task { if await store.prepareForTaskActionNavigation() { dismiss() } }
                        }.accessibilityIdentifier("task-url-back")
                    }
                }
                .navigationDestination(item: $detailID) { id in
                    if let task = store.allTasks.first(where: { $0.id == id }) { TaskDetailView(store: store, task: task) }
                }
        }
        .overlay { TaskRowDismissalOverlay(editing: store.rowEditing, close: { closeRow() }) }
        .environment(\.taskRowActions, TaskRowActions(close: { closeRow() }, information: { task in
            closeRow { detailID = task.id }
        }, reveal: { task in closeRow { detailID = task.id } }))
        .task(id: destination.id) {
            await store.reload()
            if let task = store.tasks.first(where: { $0.id == destination.taskID }) { store.expandRow(task) }
        }
        .interactiveDismissDisabled(store.rowEditing != nil || !store.presentedTaskPanels.isEmpty)
    }

    private func closeRow(after: (() -> Void)? = nil) {
        guard let row = store.rowEditing else { after?(); return }
        Task { if await row.saveAndCollapse(in: store, reduceMotion: reduceMotion) { after?() } }
    }
}

struct TaskActionMessage: ViewModifier {
    let controller: TaskURLController
    var isActive = true

    func body(content: Content) -> some View {
        content.alert("Task action", isPresented: Binding(get: { isActive && controller.message != nil }, set: { if !$0 { controller.message = nil } })) {
            Button("OK") { controller.message = nil }
        } message: { Text(controller.message ?? "") }
    }
}
