import Foundation
import SwiftUI
import UIKit
import TskCore

extension TaskStore {
    func toggleSelection(_ id: UUID) {
        guard !isSelectionSwipeActive, !isSaving else { return }
        let generation = taskSelectionGeneration
        let context = completionContext
        Task {
            guard generation == taskSelectionGeneration,
                  await finishRowEditingForSelection(), generation == taskSelectionGeneration,
                  context == completionContext else { return }
            guard visibleTasks.contains(where: { $0.id == id && $0.canComplete }) else { return }
            isSelectingTasks = true
            if !selectedTaskIDs.insert(id).inserted { selectedTaskIDs.remove(id) }
        }
    }

    func beginSelectionGesture(_ ids: Set<UUID>) async -> Bool {
        let generation = taskSelectionGeneration
        let context = completionContext
        guard !isSaving, await finishRowEditingForSelection(), !Task.isCancelled,
              generation == taskSelectionGeneration, context == completionContext else { return false }
        return activateSelectionGesture(ids)
    }

    func activateSelectionGesture(_ ids: Set<UUID>) -> Bool {
        guard !isSaving else { return false }
        selectionGestureTasks = visibleTasks
        selectionGestureDays = upcomingDays
        isSelectingTasks = true
        isSelectionGestureActive = true
        addToSelection(ids)
        return true
    }

    func addToSelection(_ ids: Set<UUID>) {
        let eligible = Set(visibleTasks.filter(\.canComplete).map(\.id))
        selectedTaskIDs.formUnion(ids.intersection(eligible))
    }

    func endSelectionGesture() {
        isSelectionGestureActive = false
        selectionGestureTasks = nil
        selectionGestureDays = nil
    }

    func endTaskSelection() {
        isSelectionSwipeActive = false
        taskSelectionGeneration += 1
        selectedTaskIDs = []
        isSelectingTasks = false
        endSelectionGesture()
    }

    func completeSelection() async {
        guard !isSaving, !isSelectionGestureActive, !selectedTaskIDs.isEmpty else { return }
        let ids = selectedTaskIDs
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await manager.complete(ids: Array(ids))
            selectedTaskIDs.subtract(ids)
            await reload()
            let remaining = Set(tasks.filter(\.canComplete).map(\.id))
            selectedTaskIDs.formIntersection(remaining)
            if selectedTaskIDs.isEmpty { endTaskSelection() }
        } catch { self.error = error.localizedDescription }
    }

    private func finishRowEditingForSelection() async -> Bool {
        rowEditing?.parameter = nil
        return await finishRowEditing(reduceMotion: UIAccessibility.isReduceMotionEnabled)
    }

    func finishRowEditing(reduceMotion: Bool) async -> Bool {
        guard let editing = rowEditing else { return true }
        guard editing.isExpanded, !editing.isSaving else { return false }
        editing.isSaving = true
        do {
            let changes = try editing.draft.changes()
            let saved = changes.isEmpty ? editing.draft.original : await update(id: editing.draft.original.id, changes: changes)
            guard let saved else {
                editing.error = error
                editing.isSaving = false
                return false
            }
            editing.savedTask = saved
            await editing.setExpanded(false, reduceMotion: reduceMotion)
            rowEditing = nil
            return true
        } catch {
            editing.error = error.localizedDescription
            editing.isSaving = false
            return false
        }
    }
}

struct TaskSelectionBar: View {
    let store: TaskStore

    var body: some View {
        VStack(spacing: 8) {
            if let error = store.error {
                Text(error).font(.callout).foregroundStyle(.red)
                    .accessibilityIdentifier("task-selection-error")
            }
            HStack {
                Button("Done") { store.endTaskSelection() }
                    .accessibilityIdentifier("task-selection-done")
                Spacer()
                Text("\(store.selectedTaskIDs.count) selected")
                    .monospacedDigit().accessibilityIdentifier("task-selection-count")
                    #if DEBUG
                    .accessibilityValue(store.selectionGestureProof)
                    #endif
                Spacer()
                Button("Complete", systemImage: "checkmark") { Task { await store.completeSelection() } }
                    .disabled(store.selectedTaskIDs.isEmpty)
                    .accessibilityIdentifier("complete-task-selection")
            }
        }
        .padding().background(.bar)
        .disabled(store.isSaving || store.isSelectionGestureActive)
    }
}
