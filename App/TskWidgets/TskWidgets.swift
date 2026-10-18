import AppIntents
import SwiftUI
import TskCore
import TskNative
import WidgetKit

struct TaskWidgetEntry: TimelineEntry {
    let date: Date
    let title: String
    let tasks: [TaskRecord]
    let count: Int
    let error: String?
}

struct TaskWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TaskWidgetEntry {
        TaskWidgetEntry(date: Date(), title: "Today", tasks: [], count: 0, error: nil)
    }

    func snapshot(for configuration: TaskWidgetConfiguration, in context: Context) async -> TaskWidgetEntry {
        await load(configuration).entry
    }

    func timeline(for configuration: TaskWidgetConfiguration, in context: Context) async -> Timeline<TaskWidgetEntry> {
        let result = await load(configuration)
        return Timeline(entries: [result.entry], policy: .after(result.refresh))
    }

    private func load(_ configuration: TaskWidgetConfiguration) async -> (entry: TaskWidgetEntry, refresh: Date) {
        let now = Date()
        do {
            guard let selected = configuration.view else { throw TaskManagementError.storage("Choose an available view in Edit Widget.") }
            let reference = try TaskViewReference(id: selected.id)
            let directory = try TaskChampionSession.participantDirectory()
            let manager = try await TaskChampionSession.open(directory: directory)
            _ = try await manager.changeVersion()
            let snapshot = try await manager.viewSnapshot(reference: reference)
            let title = try await manager.registeredViews().first(where: { $0.reference == reference })?.name ?? selected.name
            let next = snapshot.nextEvaluation ?? now.addingTimeInterval(900)
            return (TaskWidgetEntry(date: now, title: title, tasks: Array(snapshot.tasks.prefix(6)), count: snapshot.tasks.count, error: nil), max(now.addingTimeInterval(60), min(next, now.addingTimeInterval(900))))
        } catch {
            return (TaskWidgetEntry(date: now, title: "Tasks unavailable", tasks: [], count: 0, error: error.localizedDescription), now.addingTimeInterval(300))
        }
    }
}

struct TaskWidgetView: View {
    let entry: TaskWidgetEntry
    @Environment(\.widgetFamily) private var family
    private var limit: Int { family == .systemSmall ? 2 : family == .systemMedium ? 3 : 6 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.title).font(.headline).lineLimit(1)
                Spacer()
                Image(systemName: "checklist").accessibilityHidden(true)
            }
            if let error = entry.error {
                Text(error).font(.caption).foregroundStyle(.secondary)
                Text("Open tsk to retry").font(.caption)
            } else if entry.tasks.isEmpty {
                Text("No matching tasks").font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(entry.tasks.prefix(limit)) { task in
                    HStack(alignment: .top, spacing: 8) {
                        if task.canComplete {
                            Button(intent: CompleteTaskIntent(task: IntentTaskEntity(task))) {
                                Image(systemName: "circle").font(.title3)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Complete \(task.description)")
                            .accessibilityIdentifier("widget-complete-\(task.id.uuidString)")
                        } else { Image(systemName: task.status == "completed" ? "checkmark.circle.fill" : "circle.dashed").accessibilityHidden(true) }
                        Text(task.description).font(.subheadline).lineLimit(2).invalidatableContent()
                        Spacer(minLength: 0)
                    }
                }
                if entry.count > limit { Text("\(entry.count - limit) more in tsk").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct TskTaskWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "tsk.tasks", intent: TaskWidgetConfiguration.self, provider: TaskWidgetProvider()) { entry in TaskWidgetView(entry: entry) }
            .configurationDisplayName("Task view")
            .description("Today or a saved task view. Complete tasks where you see them.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct TskWidgets: WidgetBundle {
    var body: some Widget { TskTaskWidget() }
}
