import SwiftUI
import TskCore

struct TaskPlanningSection: View {
    @Binding var draft: TaskDraft
    let now: Date

    var body: some View {
        Section("Planning") {
            Toggle("Planned day", isOn: Binding(
                get: { draft.attributes["scheduled"] != nil },
                set: { draft.plannedDate = $0 ? Calendar.current.startOfDay(for: now) : nil }
            ))
            .accessibilityIdentifier("planned-day-enabled")
            if draft.attributes["scheduled"] != nil {
                if let date = draft.plannedDate {
                    DatePicker("Planned day", selection: Binding(
                        get: { date },
                        set: { draft.plannedDate = Calendar.current.startOfDay(for: $0) }
                    ), displayedComponents: .date)
                    .accessibilityIdentifier("planned-day-picker")
                } else {
                    Text("Unrecognized planned date: \(draft.attributes["scheduled"] ?? "")").font(.caption)
                }
                Button("Plan today") { draft.plannedDate = Calendar.current.startOfDay(for: now) }
                    .accessibilityIdentifier("plan-today")
                Button("Plan tomorrow") {
                    draft.plannedDate = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))
                }
                .accessibilityIdentifier("plan-tomorrow")
            }
            Toggle("Deadline", isOn: Binding(
                get: { draft.attributes["due"] != nil },
                set: { draft.deadline = $0 ? now : nil }
            ))
            .accessibilityIdentifier("deadline-enabled")
            if draft.attributes["due"] != nil {
                if let date = draft.deadline {
                    DatePicker("Deadline", selection: Binding(
                        get: { date }, set: { draft.deadline = $0 }
                    ), displayedComponents: [.date, .hourAndMinute])
                    .accessibilityIdentifier("deadline-picker")
                } else {
                    Text("Unrecognized deadline: \(draft.attributes["due"] ?? "")").font(.caption)
                    Button("Replace deadline with today") { draft.deadline = now }
                }
            }
            Text("The planned day is when you intend to work. The deadline is when the task must be finished.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}
