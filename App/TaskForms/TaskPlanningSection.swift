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
                        set: { draft.plannedDate = $0 }
                    ), displayedComponents: [.date, .hourAndMinute])
                    .accessibilityIdentifier("planned-day-picker")
                } else {
                    Text("Unrecognized scheduled date: \(draft.attributes["scheduled"] ?? "")").font(.caption)
                }
                Button("Schedule today") { draft.schedule(on: now) }
                    .accessibilityIdentifier("plan-today")
                Button("Schedule tomorrow") {
                    if let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) { draft.schedule(on: tomorrow) }
                }
                .accessibilityIdentifier("plan-tomorrow")
            }
            OptionalTaskDateEditor(title: "Deadline", identifier: "deadline", rawValue: draft.attributes["due"], date: $draft.deadline, initialDate: now)
            OptionalTaskDateEditor(title: "Waiting date", identifier: "waiting-date", rawValue: draft.attributes["wait"], date: $draft.waitUntil, initialDate: Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now)
            if draft.attributes["wait"] != nil {
                Text("Waiting tasks keep their scheduled date and deadline. A matching task stays visible in Today with its waiting reason.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Text("Scheduled is the date and time when you intend to work. The deadline is when the task must be finished.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}
