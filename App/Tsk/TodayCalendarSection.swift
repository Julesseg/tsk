import SwiftUI
import TskCore
import TskNative

struct TodayCalendarSection: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let calendar: TodayCalendarController

    var body: some View {
        if let snapshot = calendar.snapshot,
           snapshot.authorization != .fullAccess || snapshot.readError != nil || !snapshot.events.isEmpty {
            Section {
                if snapshot.authorization == .fullAccess {
                    if let error = snapshot.readError {
                        failureRow(error)
                    } else {
                        TodayCalendarOverview(snapshot: snapshot, hours: calendar.preferences.hours)
                    }
                } else {
                    Button("Enable Calendar") {
                        if snapshot.authorization == .denied || snapshot.authorization == .restricted {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        } else {
                            Task { await calendar.refresh(requestingAccess: true) }
                        }
                    }
                    .font(.subheadline)
                    .accessibilityIdentifier("calendar-request-access")
                    .accessibilityHint(snapshot.readError ?? "Show today's Calendar events. Calendar access is managed in Settings.")
                    .disabled(calendar.isLoading)
                }
                fixtureControls
            }
        }
    }

    private func failureRow(_ error: String) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Text("Calendar unavailable").foregroundStyle(.secondary).accessibilityIdentifier("calendar-read-error")
            if !dynamicTypeSize.isAccessibilitySize { Spacer() }
            Button("Retry") { Task { await calendar.refresh() } }
                .fixedSize()
                .accessibilityIdentifier("calendar-refresh")
                .accessibilityHint(error)
                .disabled(calendar.isLoading)
        }.font(.subheadline)
    }

    @ViewBuilder private var fixtureControls: some View {
        #if DEBUG && targetEnvironment(simulator)
        if calendar.fixtureVerified { Text("Actual Calendar source readback unchanged").font(.caption).accessibilityIdentifier("calendar-fixture-verified") }
        if let error = calendar.fixtureError { Text(error).foregroundStyle(.red).accessibilityIdentifier("calendar-fixture-error") }
        if let token = ProcessInfo.processInfo.environment["TSK_TEST_CALENDAR_FIXTURE"], ProcessInfo.processInfo.environment["TSK_UI_ISOLATED_SIMULATOR"] == "1", calendar.snapshot?.authorization == .fullAccess {
            Button("Add owned Calendar fixture event") {
                Task { if let day = calendar.snapshot?.day { try? await EventKitCalendarFixture.addObservedEvent(token: token, day: day) } }
            }.accessibilityIdentifier("calendar-fixture-add")
        }
        #endif
    }
}

struct TodayCalendarRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let value: TodayCalendarEvent
    let timeZone: TimeZone

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) { calendarDot; time }
                    title
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) { calendarDot; time; title }
            }
        }
        .font(.footnote)
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("calendar-event-\(value.accessibilityEventID)")
    }

    private var title: some View {
        Text(value.event.title.isEmpty ? "Untitled event" : value.event.title)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var calendarDot: some View {
        Circle().fill(value.event.color?.swiftUIColor ?? .secondary)
            .frame(width: 4, height: 4).accessibilityHidden(true)
    }

    private var time: some View {
        Text(timeDescription).font(.caption).foregroundStyle(.secondary)
            .monospacedDigit().fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
    }

    private var timeDescription: String { value.calendarTimeDescription(timeZone: timeZone) }
}

extension TodayCalendarEvent {
    var accessibilityEventID: String { Data((event.calendarID + "\u{0}" + event.eventID + "\u{0}" + String(event.start.timeIntervalSince1970)).utf8).base64EncodedString() }

    func calendarTimeDescription(timeZone: TimeZone) -> String {
        if event.isAllDay { return "All day" }
        var format = Date.FormatStyle(date: .omitted, time: .shortened)
        format.timeZone = timeZone
        if isInstant { return visibleStart.formatted(format) }
        let end = endsAtDayBoundary ? "midnight" : visibleEnd.formatted(format)
        return "\(visibleStart.formatted(format)) – \(end)"
    }
}
