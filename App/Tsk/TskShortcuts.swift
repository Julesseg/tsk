import AppIntents
import TskNative

struct TskShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CreateTaskIntent(), phrases: ["Create a task in \(.applicationName)", "Add a task to \(.applicationName)"], shortTitle: "Create Task", systemImageName: "plus.circle")
        AppShortcut(intent: FindTasksIntent(), phrases: ["Find tasks in \(.applicationName)", "Show my tasks in \(.applicationName)"], shortTitle: "Find Tasks", systemImageName: "checklist")
    }
}
