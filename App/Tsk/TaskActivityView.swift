import SwiftUI
import TskCore

struct TaskActivityCaption: View {
    let task: TaskRecord

    var body: some View {
        if task.isActive {
            VStack(alignment: .leading, spacing: 2) {
                Label(task.status == "pending" ? "Active" : "Saved start marker", systemImage: "play.circle.fill")
                if let date = task.startedAt {
                    Text("Started \(date.formatted(date: .abbreviated, time: .shortened))")
                } else { Text("Saved start timestamp is unavailable: \(task.attributes["start"] ?? "")") }
            }
            .font(.caption).foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("task-activity-\(task.id.uuidString)")
        }
    }
}

struct TaskActivityButton: View {
    let task: TaskRecord
    let store: TaskStore
    var isDetail = false
    var onSave: ((TaskRecord) -> Void)? = nil

    var body: some View {
        if task.canChangeActivity {
            Button(task.isActive ? "Stop work" : "Start work", systemImage: task.isActive ? "stop.circle" : "play.circle") {
                Task {
                    let saved = task.isActive ? await store.stop(id: task.id) : await store.start(id: task.id)
                    if let saved { onSave?(saved) }
                }
            }
            .disabled(store.isSaving)
            .accessibilityIdentifier((task.isActive ? "stop-task" : "start-task") + (isDetail ? "" : "-\(task.id.uuidString)"))
        }
    }
}
