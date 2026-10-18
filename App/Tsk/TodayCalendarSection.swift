import SwiftUI
import TskCore

struct TodayCalendarSection: View {
    @Environment(\.openURL) private var openURL
    let calendar: TodayCalendarController

    var body: some View {
        Section {
            if let snapshot = calendar.snapshot {
                if snapshot.authorization != .fullAccess, let error = snapshot.readError { Text(error).accessibilityIdentifier("calendar-permission-error") }
                switch snapshot.authorization {
                case .fullAccess:
                    if let error = snapshot.readError {
                        Text(error).accessibilityIdentifier("calendar-read-error")
                        refreshButton
                    } else if snapshot.events.isEmpty {
                        Text("No Calendar events today").foregroundStyle(.secondary).accessibilityIdentifier("calendar-empty")
                    } else {
                        ForEach(snapshot.events) { event in TodayCalendarRow(value: event, timeZone: snapshot.timeZone) }
                    }
                    if snapshot.omittedEntryCount > 0 { Text("Some duplicate or invalid Calendar entries could not be displayed.").font(.caption).foregroundStyle(.secondary) }
                case .notDetermined, .writeOnly:
                    Text("See today's events alongside your tasks. iOS requires full Calendar access to read events; tsk only displays them.").font(.footnote)
                    Button("Allow Calendar access") { Task { await calendar.refresh(requestingAccess: true) } }.accessibilityIdentifier("calendar-request-access")
                case .denied, .restricted:
                    Text(snapshot.authorization == .restricted ? "Calendar access is restricted. Your tasks are still available." : "Calendar access is denied. Your tasks are still available.").accessibilityIdentifier("calendar-permission-status")
                    if snapshot.authorization == .denied {
                        Button("Open Calendar privacy settings") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
                    }
                    refreshButton
                case .unavailable:
                    Text("Calendar access is unavailable. Your tasks are still available.")
                    refreshButton
                }
            } else { ProgressView("Loading Calendar…") }
            if calendar.fixtureVerified { Text("Actual Calendar source readback unchanged").font(.caption).accessibilityIdentifier("calendar-fixture-verified") }
            if let error = calendar.fixtureError { Text(error).foregroundStyle(.red).accessibilityIdentifier("calendar-fixture-error") }
            #if DEBUG && targetEnvironment(simulator)
            if let token = ProcessInfo.processInfo.environment["TSK_TEST_CALENDAR_FIXTURE"], ProcessInfo.processInfo.environment["TSK_UI_ISOLATED_SIMULATOR"] == "1", calendar.snapshot?.authorization == .fullAccess {
                Button("Add owned Calendar fixture event") {
                    Task { if let day = calendar.snapshot?.day { try? await TskNative.EventKitCalendarFixture.addObservedEvent(token: token, day: day) } }
                }.accessibilityIdentifier("calendar-fixture-add")
            }
            #endif
        } header: {
            HStack { Label("Calendar · Today", systemImage: "calendar"); Spacer(); if calendar.isLoading { ProgressView().controlSize(.mini) } }
        } footer: { Text("Calendar events are read only. Calendar changes never change your tasks.") }
    }

    private var refreshButton: some View {
        Button("Refresh Calendar") { Task { await calendar.refresh() } }.accessibilityIdentifier("calendar-refresh")
    }
}

import TskNative

private struct TodayCalendarRow: View {
    let value: TodayCalendarEvent
    let timeZone: TimeZone
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value.event.title.isEmpty ? "Untitled event" : value.event.title)
            Text(timeDescription).font(.subheadline).foregroundStyle(.secondary)
            if value.continuesBefore { Text("Continues from an earlier day").font(.caption).foregroundStyle(.secondary) }
            if value.continuesAfter { Text("Continues into a later day").font(.caption).foregroundStyle(.secondary) }
            Text(value.event.calendarTitle).font(.caption).foregroundStyle(.secondary)
            if let location = value.event.location, !location.isEmpty { Text(location).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.vertical, 2).accessibilityElement(children: .combine)
        .accessibilityIdentifier("calendar-event-\(Data((value.event.calendarID + "\u{0}" + value.event.eventID + "\u{0}" + String(value.event.start.timeIntervalSince1970)).utf8).base64EncodedString())")
    }
    private var timeDescription: String {
        if value.event.isAllDay { return "All day" }
        var format = Date.FormatStyle(date: .omitted, time: .shortened)
        format.timeZone = timeZone
        if value.isInstant { return value.visibleStart.formatted(format) }
        let end = value.endsAtDayBoundary ? "midnight at end of today" : value.visibleEnd.formatted(format)
        return "\(value.visibleStart.formatted(format)) – \(end)"
    }
}
