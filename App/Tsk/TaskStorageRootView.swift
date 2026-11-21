import SwiftUI
import TskNative

struct TaskStorageRootView: View {
    @State private var automation = TaskURLController()
    @State private var store: TaskStore?
    @State private var error: String?

    var body: some View {
        Group {
            if let store {
                ContentView(store: store)
            } else if let error {
                ContentUnavailableView {
                    Label("Tasks unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await open() } }
                }
                .accessibilityIdentifier("shared-storage-error")
            } else {
                ProgressView("Opening saved tasks…")
            }
        }
        .task { await open() }
        .onOpenURL { url in
            Task {
                await automation.receive(url, store: store)
                if store == nil, let error { await automation.storageUnavailable(SharedStorageError.initialization(error)) }
            }
        }
        .onChange(of: store == nil) { _, missing in
            if !missing, let store { Task { await automation.executePending(in: store) } }
        }
        .modifier(TaskActionMessage(controller: automation, isActive: store?.presentedTaskPanels.isEmpty != false && store?.rowEditing?.parameter == nil))
        .sheet(item: $automation.findResults) { results in
            if let store { TaskFindResultsView(results: results, store: store)
                    .modifier(TaskActionMessage(controller: automation, isActive: store.presentedTaskPanels.isEmpty)) }
        }
        .environment(automation)
    }

    private func open() async {
        do {
            #if DEBUG
            #if targetEnvironment(simulator)
            if let token = ProcessInfo.processInfo.environment["TSK_TEST_CALENDAR_CLEANUP"], ProcessInfo.processInfo.environment["TSK_UI_ISOLATED_SIMULATOR"] == "1" { try EventKitCalendarFixture.clean(token: token) }
            #endif
            if let description = ProcessInfo.processInfo.environment["TSK_TEST_INTENT_DESCRIPTION"] {
                _ = try await AddTaskIntent(description: description).perform()
            }
            try await installRecordedRecurrenceFixture()
            try await runTaskAutomationFixture()
            try await installNavigationFixture()
            #endif
            let opened = try TaskStore()
            store = opened
            error = nil
        } catch {
            ForegroundTaskNavigation.shared.connect { _ in throw error }
            self.error = error.localizedDescription
            await automation.storageUnavailable(error)
        }
    }
}
