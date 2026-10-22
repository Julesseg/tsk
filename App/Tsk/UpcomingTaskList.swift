import SwiftUI
import TskCore

struct UpcomingTaskList: View {
    let store: TaskStore
    var selection: Binding<UUID?>? = nil
    let edit: (TaskRecord) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            List(selection: selection) {
                ForEach(store.upcomingDays) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            TaskListRow(task: entry.task, store: store, edit: edit, dateRole: entry.role,
                                        rowIdentifier: "upcoming-\(entry.role.rawValue)-\(Int(entry.date.timeIntervalSince1970))-\(entry.task.id.uuidString)")
                                .id(entry.id)
                        }
                    } header: {
                        Text(group.day, format: .dateTime.weekday(.wide).day().month().year())
                            .accessibilityIdentifier("upcoming-day-\(Int(group.day.timeIntervalSince1970))")
                    }
                }
            }
            .accessibilityIdentifier("upcoming-list")
            .refreshable { await store.reload() }
            .onChange(of: selection?.wrappedValue) { _, id in
                if let entry = store.upcomingDays.flatMap(\.entries).first(where: { $0.task.id == id }) { proxy.scrollTo(entry.id) }
            }
        }
    }
}
