import SwiftUI
import TskCore

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
                    if controller.report?.authorization == .notDetermined {
                        Button("Allow notifications") { Task { await controller.requestPermission() } }.accessibilityIdentifier("notification-request-permission")
                    } else if controller.report?.authorization == .denied {
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
                Section("Registration") {
                    if let report = controller.report {
                        Text("\(report.registered.count) pending alerts verified with iOS").accessibilityIdentifier("notification-registered-count")
                        Text("\(report.acceptedMissed ?? 0) missed date events accepted by iOS").accessibilityIdentifier("notification-missed-accepted")
                        if !(report.retryableMissed ?? []).isEmpty {
                            Text("\(report.retryableMissed?.count ?? 0) missed alerts need retry. Allow notifications and retry reconciliation.").foregroundStyle(.orange).accessibilityIdentifier("notification-missed-retry")
                        }
                        if !(report.uncertainMissed ?? []).isEmpty {
                            Text("\(report.uncertainMissed?.count ?? 0) alert outcomes are unknown after an interruption. tsk will not resend them automatically: a missing Notification Center item may have been dismissed.").foregroundStyle(.orange).accessibilityIdentifier("notification-missed-uncertain")
                        }
                        if !report.unscheduled.isEmpty { Text("\(report.unscheduled.count) alerts are not registered. iOS may restrict capacity; retry to register the nearest upcoming alerts.").foregroundStyle(.orange).accessibilityIdentifier("notification-unscheduled") }
                        if !report.invalidTaskIDs.isEmpty { Text("\(report.invalidTaskIDs.count) tasks have unreadable alert dates.").foregroundStyle(.orange) }
                        Text("Time zone: \(report.timeZoneIdentifier)").font(.footnote)
                        ForEach(Array(report.errors.enumerated()), id: \.offset) { _, error in Text(error).foregroundStyle(.red) }
                    }
                    if let error = controller.error { Text(error).foregroundStyle(.red).accessibilityIdentifier("notification-error") }
                    Button("Retry alert reconciliation") { Task { await controller.refresh() } }.accessibilityIdentifier("notification-retry")
                    Text("Newly learned missed dates are checked after successful sync; completed or deleted tasks are excluded. Accepted events are remembered on this device. Registered alerts can be delivered while tsk is closed. Task changes on other devices take effect here after synchronization. Time zone and clock changes are reconciled when tsk next has an execution opportunity. Focus and system settings can affect delivery.").font(.footnote)
                }
                #if DEBUG
                TaskNotificationFixtureControls(controller: controller)
                MissedNotificationFixtureControls(controller: controller)
                #endif
            }
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
        switch controller.report?.authorization {
        case .authorized: "Notifications allowed"
        case .provisional: "Quiet notifications allowed"
        case .ephemeral: "Notifications temporarily allowed"
        case .denied: "Notifications disabled in system settings"
        case .notDetermined: "Notification permission has not been requested"
        default: "Notification permission unavailable"
        }
    }
}
