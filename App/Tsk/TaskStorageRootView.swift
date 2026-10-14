import SwiftUI
import TskNative

struct TaskStorageRootView: View {
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
    }

    private func open() async {
        do {
            #if DEBUG
            if let description = ProcessInfo.processInfo.environment["TSK_TEST_INTENT_DESCRIPTION"] {
                _ = try await CreateTaskIntent(description: description).perform()
            }
            try await runTaskAutomationFixture()
            #endif
            store = try TaskStore()
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}
