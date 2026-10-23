import SwiftUI
import TskCore

struct TaskPlanningSection: View {
    @Binding var draft: TaskDraft
    let now: Date

    var body: some View {
        Section("Planning") {
            Toggle("Scheduled", isOn: Binding(
                get: { draft.attributes["scheduled"] != nil },
                set: { draft.plannedDate = $0 ? Calendar.current.startOfDay(for: now) : nil }
            ))
            .accessibilityIdentifier("planned-day-enabled")
            if draft.attributes["scheduled"] != nil {
                if let date = draft.plannedDate {
                    DatePicker("Scheduled", selection: Binding(
                        get: { date },
                        set: { draft.plannedDate = Calendar.current.startOfDay(for: $0) }
                    ), displayedComponents: .date)
                    .accessibilityIdentifier("planned-day-picker")
                } else {
                    Text("Unrecognized scheduled date: \(draft.attributes["scheduled"] ?? "")").font(.caption)
                }
                Button("Schedule today") { draft.plannedDate = Calendar.current.startOfDay(for: now) }
                    .accessibilityIdentifier("plan-today")
                Button("Schedule tomorrow") {
                    draft.plannedDate = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))
                }
                .accessibilityIdentifier("plan-tomorrow")
            }
            OptionalTaskDateEditor(title: "Deadline", identifier: "deadline", rawValue: draft.attributes["due"], date: $draft.deadline, initialDate: now)
            OptionalTaskDateEditor(title: "Waiting date", identifier: "waiting-date", rawValue: draft.attributes["wait"], date: $draft.waitUntil, initialDate: Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now)
            if draft.attributes["wait"] != nil {
                Text("Waiting tasks keep their scheduled date and deadline. A matching task stays visible in Today with its waiting reason.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Text("The scheduled date is when you intend to work. The deadline is when the task must be finished.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}
