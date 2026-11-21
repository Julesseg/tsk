import SwiftUI
import TskCore

struct TaskPlanningSection: View {
    @Binding var draft: TaskDraft
    let now: Date

    var body: some View {
        Section("Planning") {
            Toggle("Scheduled", isOn: Binding(
                get: { draft.attributes["scheduled"] != nil },
                set: { draft.setScheduled($0 ? TaskScheduledDate(date: Calendar.current.startOfDay(for: now), hasTime: false) : nil) }
            ))
            .accessibilityIdentifier("planned-day-enabled")
            if draft.attributes["scheduled"] != nil {
                if let date = draft.plannedDate {
                    let hasTime = draft.scheduled()?.hasTime == true
                    let today = Calendar.current.startOfDay(for: now)
                    let selection = Binding(
                        get: { hasTime ? date : max(date, today) },
                        set: { draft.setScheduled(TaskScheduledDate(date: $0, hasTime: hasTime)) }
                    )
                    DatePicker("Scheduled", selection: selection.calendarDay(includesTime: hasTime),
                               in: (hasTime ? Date.distantPast : today)..., displayedComponents: .date)
                        .accessibilityIdentifier("planned-day-picker")
                    Toggle("Include time", isOn: Binding(
                        get: { draft.scheduled()?.hasTime ?? false },
                        set: { hasTime in
                            let value = hasTime ? date : max(today, Calendar.current.startOfDay(for: date))
                            draft.setScheduled(TaskScheduledDate(date: value, hasTime: hasTime))
                        }
                    ))
                    .accessibilityIdentifier("planned-day-has-time")
                    if hasTime {
                        DatePicker("Time", selection: selection, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.compact)
                            .accessibilityIdentifier("planned-time-picker")
                    }
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
            Text("Scheduled is the day, with an optional time, when you intend to work. The deadline is when the task must be finished.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

extension Binding where Value == Date {
    func calendarDay(includesTime: Bool) -> Self {
        Binding(get: { wrappedValue }, set: { day in
            let calendar = Calendar.autoupdatingCurrent
            if includesTime {
                let time = calendar.dateComponents([.hour, .minute, .second], from: wrappedValue)
                if let date = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: day) {
                    wrappedValue = date
                }
            } else {
                wrappedValue = calendar.startOfDay(for: day)
            }
        })
    }
}
