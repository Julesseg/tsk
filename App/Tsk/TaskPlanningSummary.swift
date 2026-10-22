import SwiftUI
import TskCore

struct TaskPlanningSummary: View {
    let task: TaskRecord
    var body: some View {
        if let date = task.plannedDate {
            LabeledContent("Planned day") { Text(date, format: .dateTime.day().month().year()) }
                .accessibilityIdentifier("task-planned-day")
        } else if let raw = task.attributes["scheduled"] {
            LabeledContent("Planned day", value: "Unrecognized date: \(raw)")
        }
        if let date = task.deadline {
            LabeledContent("Deadline") { Text(date, format: .dateTime.day().month().year().hour().minute()) }
                .accessibilityIdentifier("task-deadline")
        } else if let raw = task.attributes["due"] {
            LabeledContent("Deadline", value: "Unrecognized date: \(raw)")
        }
        if let date = task.waitUntil {
            LabeledContent("Waiting date") { Text(date, format: .dateTime.day().month().year().hour().minute()) }
                .accessibilityIdentifier("task-waiting-date")
        } else if let raw = task.attributes["wait"] {
            LabeledContent("Waiting date", value: "Unrecognized date: \(raw)")
        }
        if let date = task.startedAt {
            LabeledContent("Started") { Text(date, format: .dateTime.day().month().year().hour().minute()) }
                .accessibilityIdentifier("task-started")
        }
    }
}

struct TaskPlanningCaption: View {
    let task: TaskRecord
    var body: some View {
        if let date = task.deadline {
            Text("Deadline \(date, format: .dateTime.day().month().hour().minute())")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
