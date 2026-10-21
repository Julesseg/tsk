import SwiftUI
import TskCore

struct CalendarDisplaySettingsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let preferences: CalendarOverviewPreferences

    var body: some View {
        Form {
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
