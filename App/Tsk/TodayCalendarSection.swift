import SwiftUI
import TskCore
import TskNative

struct TodayCalendarSection: View {
    let snapshot: TodayCalendarSnapshot?

    var body: some View {
        if let snapshot,
           snapshot.authorization == .fullAccess, snapshot.readError == nil, !snapshot.allDayEvents.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(snapshot.allDayEvents) { value in
                    TodayCalendarRow(value: value, timeZone: snapshot.timeZone)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("planner-all-day-events")
        }
    }
}

struct CalendarFixtureControls: View {
    let calendar: TodayCalendarController

    @ViewBuilder var body: some View {
        #if DEBUG && targetEnvironment(simulator)
        if calendar.fixtureVerified { Text("Actual Calendar source readback unchanged").font(.caption).accessibilityIdentifier("calendar-fixture-verified") }
        if let error = calendar.fixtureError { Text(error).foregroundStyle(.red).accessibilityIdentifier("calendar-fixture-error") }
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
    var accessibilityEventID: String { event.dragAccessibilityID }

    func calendarTimeDescription(timeZone: TimeZone) -> String {
        if event.isAllDay { return "All day" }
        var format = Date.FormatStyle(date: .omitted, time: .shortened)
        format.timeZone = timeZone
        if isInstant { return visibleStart.formatted(format) }
        let end = endsAtDayBoundary ? "midnight" : visibleEnd.formatted(format)
        return "\(visibleStart.formatted(format)) – \(end)"
    }
}

extension CalendarEventSnapshot {
    var dragAccessibilityID: String {
        Data((calendarID + "\u{0}" + eventID + "\u{0}" + String(start.timeIntervalSince1970)).utf8).base64EncodedString()
    }
}
