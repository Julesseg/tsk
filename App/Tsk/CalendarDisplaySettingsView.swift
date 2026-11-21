import SwiftUI
import TskCore

struct CalendarDisplaySettingsView: View {
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
                        .accessibilityHint(snapshot.readError ?? "Show Calendar events for the displayed day. Calendar access is managed in Settings.")
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
                    Text("Choose which calendars appear on day pages.")
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

}
