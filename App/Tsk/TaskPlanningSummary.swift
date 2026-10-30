import SwiftUI
import TskCore

struct TaskPlanningSummary: View {
    let task: TaskRecord
    var body: some View {
        if let date = task.plannedDate {
            LabeledContent("Scheduled") { Text(date, format: .dateTime.day().month().year().hour().minute()) }
                .accessibilityIdentifier("task-planned-day")
        } else if let raw = task.attributes["scheduled"] {
            LabeledContent("Scheduled", value: "Unrecognized date: \(raw)")
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
    }
}

struct TaskPlanningCaption: View {
    let task: TaskRecord
    let today: Date

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let date = task.plannedDate {
                Text("\(Image(systemName: "calendar")) Scheduled \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityLabel("Scheduled \(date.formatted(date: .complete, time: .shortened))")
                    .accessibilityIdentifier("task-row-scheduled-\(task.id.uuidString)")
            }
            if let offset = task.deadlineDayOffset(relativeTo: today) {
                Text("\(Image(systemName: "flag")) Deadline \(label(offset))")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityLabel("Deadline \(label(offset))")
                    .accessibilityIdentifier("task-row-deadline-\(task.id.uuidString)")
            }
        }
    }

    private func label(_ offset: Int) -> String {
        switch offset {
        case -1: "Yesterday"
        case 0: "Today"
        case 1: "Tomorrow"
        case ..<0: "\(-offset) days ago"
        default: "In \(offset) days"
        }
    }
}
