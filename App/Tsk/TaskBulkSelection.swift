import Foundation
import SwiftUI
import UIKit
import TskCore

extension TaskStore {
    func toggleSelection(_ id: UUID) {
        guard !isSelectionPressActive, !isSaving else { return }
        if selectionDateField != nil { selectionDateField = nil; return }
        let generation = taskSelectionGeneration
        let context = completionContext
        Task {
            guard generation == taskSelectionGeneration,
                  await finishRowEditingForSelection(), generation == taskSelectionGeneration,
                  context == completionContext else { return }
            guard visibleTasks.contains(where: { $0.id == id && $0.canComplete }) else { return }
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
        guard !isSaving, selectionDateField == nil else { return false }
        selectionGestureTasks = visibleTasks
        selectionGestureDays = upcomingDays
        isSelectionGestureActive = true
        return true
    }

    func applySelectionGesture(startingAt initial: UUID, from selection: Set<UUID>, entering path: [TaskSelectionVisit]) -> Bool {
        let updated = manager.selectedTasks(in: visibleTasks, from: selection, startingAt: initial, entering: path)
        guard updated != selectedTaskIDs else { return false }
        selectedTaskIDs = updated
        return true
    }

    var selectionTasks: [TaskRecord] { allTasks.filter { selectedTaskIDs.contains($0.id) } }

    func selectionDateIsModified(_ field: TaskDateField) -> Bool {
        (try? selectionChanges.modifies(field, tasks: selectionTasks)) ?? true
    }

    var hasSelectionChanges: Bool {
        (try? selectionChanges.modifies(tasks: selectionTasks)) ?? true
    }

    func resetSelectionDate(_ field: TaskDateField) {
        selectionChanges[field] = nil
        error = nil
    }

    func toggleSelectionCompletion() {
        guard !isSaving, !isSelectionGestureActive else { return }
        selectionChanges.complete.toggle()
        error = nil
    }

    func commitTaskSelection() async {
        guard !isSaving, !isSelectionGestureActive, hasSelectionChanges else { return }
        let ids = selectedTaskIDs
        let generation = taskSelectionGeneration
        let changes = selectionChanges
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await manager.applySelection(ids: Array(ids), changes: changes)
            if generation == taskSelectionGeneration { endTaskSelection() }
            await reload()
        } catch { self.error = error.localizedDescription }
    }

    var selectionKeyboardCommands: [TaskKeyboardCommand] {
        [
            TaskKeyboardCommand(id: "selection-done", input: "\r", modifiers: [], title: "Apply to \(selectedTaskIDs.count)", action: { Task { await self.commitTaskSelection() } }),
            TaskKeyboardCommand(id: "selection-cancel", input: UIKeyCommand.inputEscape, modifiers: [], title: "Cancel", action: {
                guard !self.isSaving, !self.isSelectionGestureActive else { return }
                if self.selectionDateField != nil { self.selectionDateField = nil }
                else { self.endTaskSelection() }
            }),
            TaskKeyboardCommand(id: "selection-complete", input: "\r", modifiers: [.command, .shift], title: "Complete Selected Tasks", action: self.toggleSelectionCompletion)
        ]
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
    @Namespace private var glass

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if let error = store.error {
                Text(error).font(.callout).foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
                    .accessibilityIdentifier("task-selection-error")
            }
            GlassEffectContainer(spacing: 8) {
                VStack(alignment: .trailing, spacing: 8) {
                    dateControl(.scheduled)
                    dateControl(.deadline)
                    HStack(spacing: 12) {
                        applyButton
                        Spacer(minLength: 0)
                        completeButton
                    }
                }
            }
        }
        .font(.subheadline.weight(.semibold))
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 12).padding(.vertical, 4)
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: store.selectionDateField)
        .disabled(store.isSaving)
        .allowsHitTesting(!store.isSelectionGestureActive)
    }

    @ViewBuilder private func dateControl(_ field: TaskDateField) -> some View {
        let parameter: TaskRowParameter = field == .scheduled ? .scheduled : .deadline
        let modified = store.selectionDateIsModified(field)
        if store.selectionDateField == field {
            TaskSelectionDatePicker(store: store, field: field)
                .frame(maxWidth: 360)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.15)) { content in
                    content.glassEffect(.regular.tint(modified ? Color.accentColor.opacity(0.15) : .clear), in: RoundedRectangle(cornerRadius: 28))
                }
                .glassEffectID(field, in: glass)
                .glassEffectTransition(.matchedGeometry)
        } else {
            HStack(spacing: 0) {
                if modified {
                    Button { store.resetSelectionDate(field) } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .foregroundStyle(.orange)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .transition(.opacity)
                    .accessibilityLabel("Reset " + parameter.title.lowercased())
                    .accessibilityIdentifier("reset-selection-" + field.rawValue)
                }
                Button {
                    store.error = nil
                    store.selectionDateField = field
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: parameter.symbol)
                        if modified, let change = store.selectionChanges[field] {
                            Text(dateValue(change)).transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(field == .scheduled ? "Scheduled for selected tasks" : "Deadline for selected tasks")
                .accessibilityValue(modified ? "Modified" : "Unchanged")
                .accessibilityIdentifier("selection-" + field.rawValue)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .glassEffect(.regular.tint(modified ? Color.accentColor : .clear).interactive(), in: Capsule())
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: modified)
            .glassEffectID(field, in: glass)
            .glassEffectTransition(.matchedGeometry)
        }
    }

    private func dateValue(_ change: TaskDateChange) -> String {
        switch change {
        case .remove: "None"
        case .day(let date): date.formatted(date: .abbreviated, time: .omitted)
        case .set(let date): date.formatted(date: .abbreviated, time: .shortened)
        }
    }

    private var applyButton: some View {
        Button { Task { await store.commitTaskSelection() } } label: {
            Text(store.hasSelectionChanges ? "Apply to \(store.selectedTaskIDs.count)" : "\(store.selectedTaskIDs.count) selected")
                .contentTransition(reduceMotion ? .identity : .numericText(value: Double(store.selectedTaskIDs.count)))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .buttonStyle(TaskSelectionApplyStyle())
        .glassEffect(.regular.tint(store.hasSelectionChanges ? Color.accentColor : .clear).interactive(), in: Capsule())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: store.hasSelectionChanges)
        .animation(reduceMotion ? nil : .smooth(duration: 0.18), value: store.selectedTaskIDs.count)
        .disabled(!store.hasSelectionChanges)
        .accessibilityIdentifier("task-selection-apply")
        #if DEBUG
        .accessibilityValue(store.selectionGestureProof)
        #endif
    }

    private var completeButton: some View {
        Button("Complete selected tasks", systemImage: "checkmark") { store.toggleSelectionCompletion() }
            .labelStyle(.iconOnly)
            .frame(width: 44, height: 44)
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .glassEffect(.regular.tint(store.selectionChanges.complete ? Color.accentColor : .clear).interactive(), in: Circle())
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: store.selectionChanges.complete)
            .accessibilityValue(store.selectionChanges.complete ? "Modified" : "Unchanged")
            .accessibilityIdentifier("complete-task-selection")
    }
}

private struct TaskSelectionApplyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
    }
}
