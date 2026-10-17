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
                            NavigationLink(value: entry.task.id) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.task.description)
                                    if let project = entry.task.attributes["project"], !project.isEmpty {
                                        Text(project).font(.caption).foregroundStyle(.secondary)
                                    }
                                    HStack {
                                        Label(entry.role == .planned ? "Planned work" : "Deadline", systemImage: entry.role == .planned ? "calendar" : "flag")
                                        if entry.role == .deadline {
                                            Text(entry.date, format: .dateTime.hour().minute())
                                        }
                                    }
                                    .font(.caption).foregroundStyle(.secondary)
                                    TaskActivityCaption(task: entry.task)
                                    TaskAvailabilityView(task: entry.task, store: store)
                                    if entry.task.isRecurring {
                                        Text(entry.task.isOccurrence ? "Generated occurrence" : "Recurring template").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .tag(entry.task.id)
                            .accessibilityIdentifier("upcoming-\(entry.role.rawValue)-\(Int(entry.date.timeIntervalSince1970))-\(entry.task.id.uuidString)")
                            .contextMenu { TaskActivityButton(task: entry.task, store: store) }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                TaskActivityButton(task: entry.task, store: store).tint(.orange)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if entry.task.canComplete {
                                    Button(entry.task.isOccurrence ? "Complete occurrence" : "Complete", systemImage: "checkmark") {
                                        Task { _ = await store.complete(id: entry.task.id) }
                                    }
                                    .tint(.green).disabled(store.isSaving)
                                }
                                if entry.task.canEdit {
                                    Button(entry.task.isOccurrence ? "Edit occurrence" : "Edit", systemImage: "pencil") { edit(entry.task) }
                                        .disabled(store.isSaving)
                                }
                            }
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
