import SwiftUI
import TskCore

struct UpcomingTaskList: View {
    let store: TaskStore
    let edit: (TaskRecord) -> Void

    var body: some View {
        List {
            ForEach(store.upcomingDays) { group in
                Section {
                    ForEach(group.entries) { entry in
                        NavigationLink {
                            TaskDetailView(store: store, task: entry.task)
                        } label: {
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
                                TaskAvailabilityView(task: entry.task, store: store)
                                if entry.task.isRecurring {
                                    Text("Recurring task · read only").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityIdentifier("upcoming-\(entry.role.rawValue)-\(Int(entry.date.timeIntervalSince1970))-\(entry.task.id.uuidString)")
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if entry.task.canComplete {
                                Button("Complete", systemImage: "checkmark") {
                                    Task { _ = await store.complete(id: entry.task.id) }
                                }
                                .tint(.green).disabled(store.isSaving)
                            }
                            if entry.task.canEdit {
                                Button("Edit", systemImage: "pencil") { edit(entry.task) }
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
    }
}
