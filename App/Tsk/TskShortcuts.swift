import AppIntents
import TskNative

struct TskShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddTaskIntent(), phrases: ["Create a task in \(.applicationName)", "Add a task to \(.applicationName)"], shortTitle: "Add Task", systemImageName: "plus.circle")
        AppShortcut(intent: OpenTaskIntent(), phrases: ["Open a task in \(.applicationName)"], shortTitle: "Open Task", systemImageName: "arrow.up.forward.app")
        AppShortcut(intent: OpenTaskViewIntent(), phrases: ["Open a view in \(.applicationName)"], shortTitle: "Open View", systemImageName: "list.bullet.rectangle")
        AppShortcut(intent: FindTasksIntent(), phrases: ["Find tasks in \(.applicationName)", "Show my tasks in \(.applicationName)"], shortTitle: "Find Tasks", systemImageName: "checklist")
        AppShortcut(intent: CompleteTaskIntent(), phrases: ["Complete a task in \(.applicationName)"], shortTitle: "Complete Task", systemImageName: "checkmark.circle")
        AppShortcut(intent: RescheduleTaskIntent(), phrases: ["Reschedule a task in \(.applicationName)"], shortTitle: "Reschedule Task", systemImageName: "calendar")
    }
}
