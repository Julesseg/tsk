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
                        ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                            if index == 0 || group.entries[index - 1].role != entry.role {
                                Text(entry.role == .planned ? "Planned work" : "Deadlines")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    .accessibilityAddTraits(.isHeader)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 2, trailing: 12))
                                    .listRowSeparator(.hidden).listRowBackground(Color.clear)
                            }
                            TaskListRow(task: entry.task, store: store, edit: edit,
                                        rowIdentifier: "upcoming-\(entry.role.rawValue)-\(Int(entry.date.timeIntervalSince1970))-\(entry.task.id.uuidString)")
                                .id(entry.id)
                        }
                    } header: {
                        Text(group.day, format: .dateTime.weekday(.wide).day().month().year())
                            .accessibilityIdentifier("upcoming-day-\(Int(group.day.timeIntervalSince1970))")
                    }
                    .listSectionSeparator(.hidden)
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
