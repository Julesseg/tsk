import SwiftUI
import TskCore

struct CalendarDisplaySettingsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    let calendar: TodayCalendarController
    private var preferences: CalendarOverviewPreferences { calendar.preferences }

    var body: some View {
        Form {
            if let snapshot = calendar.snapshot {
                if snapshot.authorization != .fullAccess {
                    Section("Access") {
                        Button("Enable Calendar") {
                            if snapshot.authorization == .denied || snapshot.authorization == .restricted {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            } else {
                                Task { await calendar.refresh(requestingAccess: true) }
                            }
                        }
                        .accessibilityIdentifier("calendar-request-access")
                        .accessibilityHint(snapshot.readError ?? "Show today's Calendar events. Calendar access is managed in Settings.")
                        .disabled(calendar.isLoading)
                    }
                } else if let error = snapshot.readError {
                    Section {
                        Text("Calendar unavailable").foregroundStyle(.secondary)
                            .accessibilityIdentifier("calendar-read-error")
                        Button("Retry") { Task { await calendar.refresh() } }
                            .accessibilityIdentifier("calendar-refresh")
                            .accessibilityHint(error)
                            .disabled(calendar.isLoading)
                    }
                }
            }
            Section {
                Stepper(value: Binding(get: { preferences.hours.startHour }, set: {
                    preferences.hours = CalendarDisplayHours(startHour: $0, endHour: preferences.hours.endHour)
                }), in: 0...(preferences.hours.endHour - 1)) {
                    hourLabel("Start hour", value: preferences.hours.startHour)
                }
                .accessibilityIdentifier("calendar-start-hour")
                .accessibilityValue(hour(preferences.hours.startHour))
                Stepper(value: Binding(get: { preferences.hours.endHour }, set: {
                    preferences.hours = CalendarDisplayHours(startHour: preferences.hours.startHour, endHour: $0)
                }), in: (preferences.hours.startHour + 1)...24) {
                    hourLabel("End hour", value: preferences.hours.endHour)
                }
                .accessibilityIdentifier("calendar-end-hour")
                .accessibilityValue(hour(preferences.hours.endHour))
            } header: {
                Text("Day overview")
            } footer: {
                Text("Events outside these hours remain visible below the overview.")
            }
        }
        .navigationTitle("Calendar")
        .accessibilityIdentifier("calendar-display-settings-form")
        .task { await calendar.refreshAuthorization() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await calendar.refreshAuthorization() } }
        }
    }

    private func hour(_ value: Int) -> String { String(format: "%02d:00", value) }

    @ViewBuilder private func hourLabel(_ title: String, value: Int) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(hour(value)).monospacedDigit().foregroundStyle(.secondary).fixedSize()
            }
        } else {
            LabeledContent(title, value: hour(value))
        }
    }
}
