import Foundation
import SwiftUI
import UIKit
import TskCore

extension TaskStore {
    func toggleSelection(_ id: UUID) {
        guard !isSelectionPressActive, !isSaving else { return }
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

    func beginSelectionGesture() async -> Bool {
        let generation = taskSelectionGeneration
        let context = completionContext
        guard !isSaving, await finishRowEditingForSelection(), !Task.isCancelled,
              generation == taskSelectionGeneration, context == completionContext else { return false }
        return activateSelectionGesture()
    }

    func activateSelectionGesture() -> Bool {
        guard !isSaving else { return false }
        selectionGestureTasks = visibleTasks
        selectionGestureDays = upcomingDays
        isSelectingTasks = true
        isSelectionGestureActive = true
        return true
    }

    func applySelectionGesture(startingAt initial: UUID, from selection: Set<UUID>, entering path: [TaskSelectionVisit]) -> Bool {
        let updated = manager.selectedTasks(in: visibleTasks, from: selection, startingAt: initial, entering: path)
        guard updated != selectedTaskIDs else { return false }
        selectedTaskIDs = updated
        return true
    }

    func endSelectionGesture() {
        isSelectionGestureActive = false
        selectionGestureTasks = nil
        selectionGestureDays = nil
    }

    func endTaskSelection() {
        isSelectionPressActive = false
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
        return await editing.saveAndCollapse(in: self, reduceMotion: reduceMotion)
    }
}

struct TaskSelectionBar: View {
    let store: TaskStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 8) {
            if let error = store.error {
                Text(error).font(.callout).foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityIdentifier("task-selection-error")
            }
            GlassEffectContainer(spacing: 8) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        doneButton
                        selectionCount
                        completeButton
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    VStack(spacing: 10) {
                        doneButton
                        selectionCount
                        completeButton
                    }
                }
                .font(.subheadline.weight(.semibold))
                .controlSize(.large)
                .buttonBorderShape(.capsule)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .opacity(appeared ? 1 : 0)
        .offset(y: reduceMotion || appeared ? 0 : 12)
        .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { appeared = true } }
        .disabled(store.isSaving || store.isSelectionGestureActive)
    }

    private var doneButton: some View {
        Button("Done") { store.endTaskSelection() }
            .buttonStyle(.glass)
            .accessibilityIdentifier("task-selection-done")
    }

    private var selectionCount: some View {
        Text("\(store.selectedTaskIDs.count) selected")
            .contentTransition(reduceMotion ? .identity : .numericText(value: Double(store.selectedTaskIDs.count)))
            .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: store.selectedTaskIDs.count)
            .monospacedDigit()
            .padding(.horizontal, 16).padding(.vertical, 12)
            .glassEffect(.regular, in: Capsule())
            .accessibilityIdentifier("task-selection-count")
            #if DEBUG
            .accessibilityValue(store.selectionGestureProof)
            #endif
    }

    private var completeButton: some View {
        Button("Complete", systemImage: "checkmark") { Task { await store.completeSelection() } }
            .buttonStyle(.glassProminent)
            .disabled(store.selectedTaskIDs.isEmpty)
            .accessibilityIdentifier("complete-task-selection")
    }
}
