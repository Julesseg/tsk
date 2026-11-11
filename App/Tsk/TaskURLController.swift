import Foundation
import Observation
import SwiftUI
import TskCore
import UIKit

@MainActor @Observable
final class TaskURLController {
    var findResults: TaskFindResults?
    var taskToOpen: TaskRecord?
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
                case .add(let input):
                    task = try await store.manager.addTask(input)
                    saved = task
                case .openTask(let id): task = try await store.manager.task(id: id)
                }
                let callback = try callbacks?.successURL(for: task)
                await store.reload()
                if let callback {
                    await deliver(callback, saved: saved)
                } else if case .openTask = action {
                    taskToOpen = task
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

struct TaskActionMessage: ViewModifier {
    let controller: TaskURLController
    var isActive = true

    func body(content: Content) -> some View {
        content.alert("Task action", isPresented: Binding(get: { isActive && controller.message != nil }, set: { if !$0 { controller.message = nil } })) {
            Button("OK") { controller.message = nil }
        } message: { Text(controller.message ?? "") }
    }
}
