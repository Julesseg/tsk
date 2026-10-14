import AppIntents
import SwiftUI

struct TaskShortcutsView: View {
    var body: some View {
        Form {
            Section("Create and find tasks") {
                Text("Use Create Task and Find Tasks in Shortcuts, or ask Siri to create a task in tsk.")
                Text("Created tasks use the same saved tasks and synchronization connection as this app. They are saved locally before the action finishes.")
                ShortcutsLink()
            }
            Section("Synchronization") {
                Text("Actions request synchronization after saving. If the network is unavailable or an action ends in the background, opening tsk or Retry continues synchronization.")
            }
        }
        .navigationTitle("Shortcuts and Siri")
    }
}
