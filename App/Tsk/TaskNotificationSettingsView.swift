import SwiftUI
import TskCore
import TskNative

struct TaskNotificationSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let controller: TaskNotificationController
    @State private var replaceMidnight = true
    @State private var time = Date()
    @State private var loaded = false
    var body: some View {
        NavigationStack {
            Form {
                if controller.isWorking { ProgressView("Checking system notifications…") }
                Section("System permission") {
                    Text(permissionText).accessibilityIdentifier("notification-permission")
                    if controller.authorization == .notDetermined {
                        Button("Allow notifications") { Task { await controller.requestPermission() } }.accessibilityIdentifier("notification-request-permission")
                    } else if controller.authorization == .denied {
                        Link("Open notification settings", destination: URL(string: UIApplication.openNotificationSettingsURLString)!)
                    }
                    Text("Tasks remain available when notifications are disabled.").font(.footnote)
                }
                Section("Midnight task dates") {
                    Toggle("Replace midnight alert time", isOn: $replaceMidnight).accessibilityIdentifier("notification-midnight-enabled")
                    if replaceMidnight { DatePicker("Alert time", selection: $time, displayedComponents: .hourAndMinute).accessibilityIdentifier("notification-midnight-time") }
                    Text("Uses the current device time zone. Task dates and other alert times stay unchanged. At a daylight saving gap the next valid time is used; a repeated time uses its first occurrence.").font(.footnote)
                    Button("Save alert preferences") {
                        let clock = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: time)
                        Task { await controller.save(TaskNotificationPreferences(midnightReplacement: replaceMidnight, hour: clock.hour ?? 9, minute: clock.minute ?? 0)) }
                    }.accessibilityIdentifier("notification-save-preferences")
                }
                if let error = controller.error {
                    Text(error).foregroundStyle(.red).accessibilityIdentifier("notification-error")
                }
                #if DEBUG
                TaskNotificationFixtureControls(controller: controller)
                MissedNotificationFixtureControls(controller: controller)
                #endif
            }
            .accessibilityIdentifier("notification-settings-form")
            .onAppear { TaskParticipantDiagnostics.event("notifications.presentation.appeared", details: [:]) }
            .onDisappear { TaskParticipantDiagnostics.event("notifications.presentation.disappeared", details: [:]) }
            .navigationTitle("Task notifications")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task {
                await controller.refresh()
                guard !loaded else { return }
                loaded = true
                replaceMidnight = controller.preferences.midnightReplacement
                time = Calendar.autoupdatingCurrent.date(bySettingHour: controller.preferences.hour, minute: controller.preferences.minute, second: 0, of: Date()) ?? Date()
            }
        }
    }
    private var permissionText: String {
        switch controller.authorization {
        case .authorized: "Notifications allowed"
        case .provisional: "Quiet notifications allowed"
        case .ephemeral: "Notifications temporarily allowed"
        case .denied: "Notifications disabled in system settings"
        case .notDetermined: "Notification permission has not been requested"
        default: "Notification permission unavailable"
        }
    }
}
