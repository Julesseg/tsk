import SwiftUI
import TskCore
import TskNative

struct SpotlightStatusView: View {
    @Environment(\.dismiss) private var dismiss
    let controller: SpotlightController
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Find unfinished tasks in system Spotlight, then open the exact task in tsk. Task descriptions, projects and tags are indexed on this device.")
                    Text("Completed and deleted tasks are removed from new index updates. An old result always checks current storage before opening.").font(.footnote).foregroundStyle(.secondary)
                    if let count = controller.status?.indexedCount { Text("Indexed \(count) task(s)").accessibilityIdentifier("spotlight-index-count") }
                    if let date = controller.status?.lastSuccessfulIndex { LabeledContent("Last index update", value: date.formatted()) }
                    if let error = controller.status?.error { Text(error).foregroundStyle(.red).accessibilityIdentifier("spotlight-index-error") }
                    Button("Update Spotlight index") { Task { await controller.reconcile() } }.disabled(controller.isRefreshing).accessibilityIdentifier("spotlight-reconcile")
                    Button("Check indexed tasks") { Task { await controller.query() } }.disabled(controller.isRefreshing).accessibilityIdentifier("spotlight-query")
                    if let result = controller.queryResult { Text(result).accessibilityIdentifier("spotlight-query-result") }
                    if let error = controller.error { Text(error).foregroundStyle(.red).accessibilityIdentifier("spotlight-query-error") }
                    if controller.isRefreshing { ProgressView("Updating Spotlight…") }
                }
                #if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.environment["TSK_TEST_SPOTLIGHT_FIXTURE"] != nil, ProcessInfo.processInfo.environment["TSK_UI_ISOLATED_SIMULATOR"] == "1" {
                    Section("Isolated fixture") {
                        if controller.queryResult != nil { Text(controller.queryItems.isEmpty ? "No indexed UUIDs" : controller.queryItems.map(\.identifier).joined(separator: "\n")).accessibilityIdentifier("spotlight-fixture-query-ids") }
                        if let result = controller.fixtureResult { Text(result).accessibilityIdentifier("spotlight-fixture-result") }
                        Button("Index unavailable fixture result") { Task { await controller.fixture(stale: true) } }.accessibilityIdentifier("spotlight-stale-fixture")
                        Button("Write received fixture state") { Task { await controller.fixture(stale: false) } }.accessibilityIdentifier("spotlight-sync-fixture")
                    }
                }
                #endif
            }.accessibilityIdentifier("spotlight-settings-form")
                .navigationTitle("Spotlight").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
                .task { controller.loadStatus() }
        }
    }
}

struct SpotlightRequest: Identifiable {
    let id = UUID()
    let identifier: String
}

struct SpotlightTaskDestination: View {
    @Environment(\.dismiss) private var dismiss
    let store: TaskStore
    let identifier: String
    @State private var task: TaskRecord?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Group {
                if let error {
                    ContentUnavailableView {
                        Label("Task unavailable", systemImage: "magnifyingglass")
                    } description: { Text(error) } actions: {
                        Button("Retry exact task") { Task { await resolve() } }
                    }.accessibilityIdentifier("spotlight-task-unavailable")
                } else if let task { TaskDetailView(store: store, task: task).id(task.id) }
                else { ProgressView("Opening current task…") }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
        .task { await store.reload(); await resolve() }
        .onChange(of: store.allTasks) { _, _ in Task { await resolve() } }
        .modifier(TaskWorkspacePanel(store: store))
    }
    private func resolve() async {
        do { task = try await store.manager.resolveSpotlight(identifier: identifier, namespace: SpotlightTaskEffect.namespace(directory: store.directory)); error = nil }
        catch { task = nil; self.error = error.localizedDescription }
    }
}
