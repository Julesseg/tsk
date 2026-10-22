import SwiftUI
import TskCore

struct UpcomingTaskList: View {
    let store: TaskStore
    var selection: Binding<UUID?>? = nil
    let edit: (TaskRecord) -> Void
    var viewportHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                                        rowIdentifier: entry.rowIdentifier)
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
            .task(id: viewportHeight) {
                await Task.yield()
                if let entry = store.upcomingDays.flatMap(\.entries).first(where: { $0.rowIdentifier == store.rowEditing?.rowID }) {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.32)) { proxy.scrollTo(entry.id, anchor: .top) }
                }
            }
            .onChange(of: store.rowEditing?.rowID) { _, rowID in
                if let entry = store.upcomingDays.flatMap(\.entries).first(where: { $0.rowIdentifier == rowID }) {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.32)) { proxy.scrollTo(entry.id, anchor: .top) }
                }
            }
            .onChange(of: selection?.wrappedValue) { _, id in
                if let entry = store.upcomingDays.flatMap(\.entries).first(where: { $0.task.id == id }) { proxy.scrollTo(entry.id) }
            }
        }
    }
}
