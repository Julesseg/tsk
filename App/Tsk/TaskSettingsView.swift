import SwiftUI

struct TaskSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let calendar: TodayCalendarController
    let choose: (ContentView.WorkspaceSetting) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Tasks") {
                    Button("Views", systemImage: "square.grid.2x2") { choose(.customViews) }
                        .accessibilityIdentifier("custom-views")
                    Button("Recurring templates", systemImage: "repeat") { choose(.recurring) }
                        .accessibilityIdentifier("recurring-templates")
                    Button("Attribute definitions", systemImage: "slider.horizontal.3") { choose(.attributeDefinitions) }
                        .accessibilityIdentifier("attribute-definitions")
                }
                Section("Integrations") {
                    NavigationLink {
                        CalendarDisplaySettingsView(calendar: calendar)
                    } label: {
                        Label("Calendar", systemImage: "calendar")
                    }.accessibilityIdentifier("calendar-display-settings")
                    Button("Synchronization", systemImage: "arrow.triangle.2.circlepath") { choose(.synchronization) }
                        .accessibilityIdentifier("synchronization-settings")
                    Button("Task notifications", systemImage: "bell") { choose(.notifications) }
                        .accessibilityIdentifier("notification-settings")
                    Button("Copy from Reminders", systemImage: "square.and.arrow.down") { choose(.remindersImport) }
                        .accessibilityIdentifier("reminders-import")
                    Button("Move from Reminders automatically", systemImage: "arrow.down.forward.circle") { choose(.continuousReminders) }
                        .accessibilityIdentifier("continuous-reminders-settings")
                }
                #if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.environment["TSK_TEST_SPOTLIGHT_FIXTURE"] != nil,
                   ProcessInfo.processInfo.environment["TSK_UI_ISOLATED_SIMULATOR"] == "1" {
                    Section("Test diagnostics") {
                        Button("Spotlight diagnostics") { choose(.spotlightDiagnostics) }
                            .accessibilityIdentifier("spotlight-diagnostics")
                    }
                }
                #endif
            }
            .accessibilityIdentifier("workspace-settings-list")
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("close-workspace-settings")
                }
            }
        }
        .tint(.primary)
    }
}
