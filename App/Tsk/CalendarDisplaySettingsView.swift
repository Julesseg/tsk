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
            if let snapshot = calendar.snapshot, snapshot.authorization == .fullAccess {
                Section {
                    ForEach(snapshot.calendars) { item in
                        HStack(spacing: 10) {
                            Circle().fill(item.color?.swiftUIColor ?? .secondary)
                                .frame(width: 8, height: 8).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title.isEmpty ? "Untitled calendar" : item.title)
                                Text(item.sourceTitle).font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityHidden(true)
                            Toggle("Calendar visibility", isOn: Binding(get: { preferences.visibility.isVisible(item.calendarID) }, set: {
                                preferences.visibility.setVisible($0, calendarID: item.calendarID)
                            }))
                            .labelsHidden()
                            .accessibilityLabel("\(item.title.isEmpty ? "Untitled calendar" : item.title), \(item.sourceTitle)")
                            .accessibilityIdentifier("calendar-visibility-\(item.calendarID)")
                        }
                    }
                    if snapshot.calendars.isEmpty, snapshot.readError == nil {
                        Text("No calendars available").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Show calendars")
                } footer: {
                    Text("Choose which calendars appear in Today.")
                }
            }
        }
        .navigationTitle("Calendar")
        .accessibilityIdentifier("calendar-display-settings-form")
        .onAppear { calendar.isDisplayingSettings = true }
        .onDisappear { calendar.isDisplayingSettings = false }
        .task { await calendar.refreshSettings() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await calendar.refreshSettings() } }
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
