import Foundation
import Observation
import SwiftUI
import TskCore
import UIKit

@MainActor @Observable
final class TaskURLController {
    var taskToOpen: TaskRecord?
    var deletedTaskID: UUID?
    var findResults: TaskFindResults?
    @ObservationIgnored var navigate: (@MainActor (TaskNavigationDestination) async throws -> Void)?
    var message: String?
    private var requests: [URL] = []
    private var isExecuting = false

    func receive(_ url: URL, store: TaskStore?) async {
        requests.append(url)
        if let store { await executePending(in: store) }
    }

    func executePending(in store: TaskStore) async {
        guard !isExecuting, store.workspaceViewsLoaded, navigate != nil else { return }
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
                if case .complete(let id) = action {
                    _ = try await store.manager.task(id: id, includingDeleted: false)
                }
                if case .delete(let id) = action {
                    _ = try await store.manager.task(id: id)
                }
                guard await store.prepareForTaskActionNavigation() else {
                    throw TaskActionError.navigationFailed(store.error ?? "Finish the current editing panel before opening a task URL.")
                }
                let task: TaskRecord
                switch action {
                case .find(let input):
                    let tasks = try await store.manager.findTasks(input)
                    if let callback = try callbacks?.successURL(for: tasks) {
                        await deliver(callback, saved: nil)
                    } else {
                        await store.reload()
                        findResults = TaskFindResults(tasks: tasks)
                    }
                    continue
                case .openTask, .openView:
                    let destination = try await resolveNavigation(action, in: store)
                    let callback = try callbacks?.navigationURL(for: destination)
                    guard let navigate else { throw TaskActionError.navigationFailed("The task workspace is unavailable.") }
                    try await navigate(destination)
                    if let callback { await deliver(callback, saved: nil) }
                    continue
                case .delete(let id):
                    task = try await store.manager.delete(id: id)
                    deletedTaskID = task.id
                case .complete(let id): task = try await store.manager.complete(id: id)
                case .add(let input): task = try await store.manager.addTask(input)
                case .modify(let id, let input): task = try await store.manager.modifyTask(id: id, input: input)
                }
                saved = task
                await store.reload()
                let callback = try callbacks?.successURL(for: task)
                if let callback {
                    await deliver(callback, saved: saved)
                } else if case .delete = action {
                    taskToOpen = nil
                    message = "Deletion saved locally: \(task.description) (\(task.id.uuidString))."
                } else if case .complete = action {
                    taskToOpen = task
                } else if case .modify = action {
                    guard let navigate else { throw TaskActionError.navigationFailed("The task workspace is unavailable.") }
                    try await navigate(store.manager.navigationDestination(taskID: task.id))
                }
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

    func openForeground(_ action: TaskActionURL, in store: TaskStore) async throws {
        guard !isExecuting, let navigate else { throw TaskActionError.navigationFailed("Another task action is running. Try again.") }
        isExecuting = true
        defer { isExecuting = false }
        guard await store.prepareForTaskActionNavigation() else {
            throw TaskActionError.navigationFailed(store.error ?? "Finish the current task draft before navigating.")
        }
        try await navigate(resolveNavigation(action, in: store))
    }

    private func resolveNavigation(_ action: TaskActionURL, in store: TaskStore) async throws -> TaskNavigationDestination {
        switch action {
        case .openTask(let id): try await store.manager.navigationDestination(taskID: id)
        case .openView(let view): try await store.manager.navigationDestination(view: view)
        case .add, .find, .modify, .complete, .delete: throw TaskActionError.invalidInput("Data actions do not use foreground navigation.")
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
            message = "Task saved locally (\(saved.id.uuidString)), but the callback could not be delivered. The task was not undone or retried."
        } else { message = "The callback could not be delivered. " + (message ?? "") }
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
