import SwiftUI
import TskCore
import UIKit

struct TaskWorkspaceActions {
    let capture: () -> Void
    let edit: (() -> Void)?
    let complete: (() -> Void)?
    let move: (TaskSelectionMovement) -> Void
    let reveal: (() -> Void)?
    let openView: (TaskQuery) -> Void
    let refresh: () -> Void

    var keyboardCommands: [TaskKeyboardCommand] {
        var commands = [
            TaskKeyboardCommand(id: "capture", input: "n", modifiers: .command, title: "New Task", action: capture),
            TaskKeyboardCommand(id: "previous", input: UIKeyCommand.inputUpArrow, modifiers: .command, title: "Previous Task", action: { move(.previous) }),
            TaskKeyboardCommand(id: "next", input: UIKeyCommand.inputDownArrow, modifiers: .command, title: "Next Task", action: { move(.next) }),
            TaskKeyboardCommand(id: "today", input: "1", modifiers: .command, title: "Today", action: { openView(.today) }),
            TaskKeyboardCommand(id: "upcoming", input: "2", modifiers: .command, title: "Upcoming", action: { openView(.upcoming) }),
            TaskKeyboardCommand(id: "unfinished", input: "3", modifiers: .command, title: "All", action: { openView(.unfinished) }),
            TaskKeyboardCommand(id: "completed", input: "4", modifiers: .command, title: "Done", action: { openView(.completed) }),
            TaskKeyboardCommand(id: "refresh", input: "r", modifiers: .command, title: "Refresh Tasks", action: refresh)
        ]
        if let edit { commands.append(TaskKeyboardCommand(id: "edit", input: "e", modifiers: .command, title: "Edit Task", action: edit)) }
        if let complete { commands.append(TaskKeyboardCommand(id: "complete", input: "\r", modifiers: [.command, .shift], title: "Complete Task", action: complete)) }
        if let reveal { commands.append(TaskKeyboardCommand(id: "reveal", input: "o", modifiers: .command, title: "Reveal Task Details", action: reveal)) }
        return commands
    }
}

struct TaskEditorActions {
    let save: () -> Void
    var keyboardCommands: [TaskKeyboardCommand] {
        TaskKeyboardCommand.suspended + [TaskKeyboardCommand(id: "save", input: "\r", modifiers: .command, title: "Save Changes", action: save)]
    }
}
