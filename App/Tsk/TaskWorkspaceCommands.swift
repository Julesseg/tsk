import SwiftUI
import TskCore

struct TaskWorkspaceActions {
    let capture: () -> Void
    let edit: (() -> Void)?
    let complete: (() -> Void)?
    let move: (TaskSelectionMovement) -> Void
    let reveal: (() -> Void)?
    let openView: (TaskQuery) -> Void
    let refresh: () -> Void
}

private struct TaskWorkspaceActionsKey: FocusedValueKey {
    typealias Value = TaskWorkspaceActions
}

extension FocusedValues {
    var taskWorkspace: TaskWorkspaceActions? {
        get { self[TaskWorkspaceActionsKey.self] }
        set { self[TaskWorkspaceActionsKey.self] = newValue }
    }
}

struct TaskWorkspaceCommands: Commands {
    @FocusedValue(\.taskWorkspace) private var actions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Task") { actions?.capture() }
                .keyboardShortcut("n", modifiers: .command).disabled(actions == nil)
        }
        CommandMenu("Tasks") {
            Button("Previous Task") { actions?.move(.previous) }
                .keyboardShortcut(.upArrow, modifiers: .command).disabled(actions == nil)
            Button("Next Task") { actions?.move(.next) }
                .keyboardShortcut(.downArrow, modifiers: .command).disabled(actions == nil)
            Button("Reveal Task Details") { actions?.reveal?() }
                .keyboardShortcut("o", modifiers: .command).disabled(actions?.reveal == nil)
            Button("Edit Task") { actions?.edit?() }
                .keyboardShortcut("e", modifiers: .command).disabled(actions?.edit == nil)
            Button("Complete Task") { actions?.complete?() }
                .keyboardShortcut(.return, modifiers: [.command, .shift]).disabled(actions?.complete == nil)
            Divider()
            Button("Today") { actions?.openView(.today) }.keyboardShortcut("1", modifiers: .command).disabled(actions == nil)
            Button("Upcoming") { actions?.openView(.upcoming) }.keyboardShortcut("2", modifiers: .command).disabled(actions == nil)
            Button("Unfinished") { actions?.openView(.unfinished) }.keyboardShortcut("3", modifiers: .command).disabled(actions == nil)
            Button("Completed") { actions?.openView(.completed) }.keyboardShortcut("4", modifiers: .command).disabled(actions == nil)
            Divider()
            Button("Refresh Tasks") { actions?.refresh() }
                .keyboardShortcut("r", modifiers: .command).disabled(actions == nil)
        }
    }
}
