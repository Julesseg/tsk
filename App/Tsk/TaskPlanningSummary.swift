import SwiftUI
import TskCore

struct TaskPlanningSummary: View {
    let task: TaskRecord
    var body: some View {
        if let date = task.plannedDate {
            LabeledContent("Scheduled") {
                Text(date.formatted(date: .abbreviated, time: task.scheduled()?.hasTime == true ? .shortened : .omitted))
            }
                .accessibilityIdentifier("task-planned-day")
        } else if let raw = task.attributes["scheduled"] {
            LabeledContent("Scheduled", value: "Unrecognized date: \(raw)")
        }
        if let intent = task.dateIntent(for: .deadline) {
            LabeledContent("Deadline") {
                Text(intent.date.formatted(date: .abbreviated, time: intent.hasTime ? .shortened : .omitted))
            }
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
    @ScaledMetric(relativeTo: .caption2) private var textSize: CGFloat = 10

    var body: some View {
        if let deadline = task.dateIntent(for: .deadline), let offset = task.deadlineDayOffset(relativeTo: today) {
            Text("\(Image(systemName: "flag")) \(label(offset, abbreviated: true))")
                .font(.system(size: textSize))
                .foregroundStyle(task.status == "pending" && (deadline.hasTime ? deadline.date < today : offset < 0) ? Color.red : Color.secondary)
                .accessibilityLabel("Deadline \(label(offset))")
                .accessibilityIdentifier("task-row-deadline-\(task.id.uuidString)")
        }
    }

    private func label(_ offset: Int, abbreviated: Bool = false) -> String {
        switch offset {
        case -1: abbreviated ? "yes." : "Yesterday"
        case 0: abbreviated ? "tod." : "Today"
        case 1: abbreviated ? "tom." : "Tomorrow"
        case ..<0: abbreviated ? "\(-offset)d ago" : "\(-offset) days ago"
        default: "In \(offset) days"
        }
    }
}
