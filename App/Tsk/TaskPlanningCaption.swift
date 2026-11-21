import SwiftUI
import TskCore

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
