import AppIntents
import SwiftUI

struct TaskShortcutsView: View {
    var body: some View {
        Form {
            Section("Task actions") {
                Text("Use Create Task, Find Tasks, Complete Task, and Reschedule Task in Shortcuts, or ask Siri to create a task in tsk.")
                Text("All actions use the same saved tasks and synchronization connection as this app. They are saved locally before the action finishes.")
                Text("Reschedule Task changes either Planned day or Deadline. Choose the date role explicitly; the other date stays unchanged.")
                ShortcutsLink()
            }
            Section("Synchronization") {
                Text("Actions request synchronization after saving. If the network is unavailable or an action ends in the background, opening tsk or Retry continues synchronization.")
            }
        }
        .navigationTitle("Shortcuts and Siri")
    }
}
