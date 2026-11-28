import SwiftUI
import TskCore

struct TaskPlanningCaption: View {
    let task: TaskRecord
    let today: Date
    var showsEmptyFlag = false
    @ScaledMetric(relativeTo: .caption2) private var textSize: CGFloat = 12

    var body: some View {
        if let deadline = task.dateIntent(for: .deadline), let offset = task.deadlineDayOffset(relativeTo: today) {
            let label = switch offset {
            case -1: "Yesterday"
            case 0: "Today"
            case 1: "Tomorrow"
            default: deadline.date.formatted(.dateTime.month(.abbreviated).day())
            }
            Text("\(Image(systemName: "flag")) \(label)")
                .font(.system(size: textSize))
                .foregroundStyle(task.status == "pending" && (deadline.hasTime ? deadline.date < today : offset < 0) ? Color.red : Color.secondary)
                .accessibilityLabel("Deadline \(label)")
                .accessibilityIdentifier("task-row-deadline-\(task.id.uuidString)")
        } else if showsEmptyFlag {
            Image(systemName: "flag")
                .font(.system(size: textSize))
                .foregroundStyle(.tertiary)
                .frame(minWidth: 28, alignment: .trailing)
        }
    }
}
