import SwiftUI
import TskNative
import CoreSpotlight

struct TaskStorageRootView: View {
    @State private var store: TaskStore?
    @State private var error: String?
    @State private var spotlightRequest: SpotlightRequest?

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
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            spotlightRequest = SpotlightRequest(identifier: activity.userInfo?[CSSearchableItemActivityIdentifier] as? String ?? "")
        }
        .sheet(item: $spotlightRequest) { request in
            if let store { SpotlightTaskDestination(store: store, identifier: request.identifier) }
            else { ContentUnavailableView("Task storage unavailable", systemImage: "exclamationmark.triangle", description: Text(error ?? "Saved tasks could not be opened.")) }
        }
    }

    private func open() async {
        do {
            #if DEBUG
            #if targetEnvironment(simulator)
            if let token = ProcessInfo.processInfo.environment["TSK_TEST_CALENDAR_CLEANUP"], ProcessInfo.processInfo.environment["TSK_UI_ISOLATED_SIMULATOR"] == "1" { try EventKitCalendarFixture.clean(token: token) }
            #endif
            try cleanReminderFixtureIfRequested()
            try addForegroundReminderFixtureIfRequested()
            if let description = ProcessInfo.processInfo.environment["TSK_TEST_INTENT_DESCRIPTION"] {
                _ = try await CreateTaskIntent(description: description).perform()
            }
            try await installRecordedRecurrenceFixture()
            try await runTaskAutomationFixture()
            try await installWidgetFixture()
            #endif
            store = try TaskStore()
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}
