import SwiftUI
import TskCore

struct TodayCalendarOverview: View {
    let snapshot: TodayCalendarSnapshot
    let hours: CalendarDisplayHours
    let acceptsTaskDrops: Bool
    @ScaledMetric(relativeTo: .caption2) private var labelSize = 10

    private var overview: CalendarOverview { CalendarOverview(snapshot: snapshot, hours: hours) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(overview.allDay) { value in
                TodayCalendarRow(value: value, timeZone: snapshot.timeZone)
                    .opensCalendarEvent(value.event)
            }
            if !overview.items.isEmpty {
                VStack(spacing: 8) {
                    hourRuler
                    CalendarOverviewLayout(items: overview.items) {
                        ForEach(overview.items) { item in
                            Text(item.value.event.title.isEmpty ? "Untitled event" : item.value.event.title)
                                .font(.system(size: labelSize))
                                .fixedSize(horizontal: false, vertical: true)
                                .background(Color(uiColor: .systemGroupedBackground))
                                .opensCalendarEvent(item.value.event)
                                .calendarDropTarget(item.value.event, enabled: acceptsTaskDrops)
                                .accessibilityLabel("\(item.value.calendarTimeDescription(timeZone: snapshot.timeZone)), \(item.value.event.title.isEmpty ? "Untitled event" : item.value.event.title)")
                                .accessibilityIdentifier("calendar-event-\(item.value.accessibilityEventID)")
                            Capsule().fill(item.value.event.color?.swiftUIColor ?? .secondary)
                                .opensCalendarEvent(item.value.event)
                                .calendarDropTarget(item.value.event, enabled: acceptsTaskDrops)
                                .accessibilityHidden(true)
                        }
                    }
                    .background { nowMarker }
                }
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("calendar-day-overview")
                .accessibilityValue("\(hours.startHour):00–\(hours.endHour):00")
            }
            ForEach(overview.outsideHours) { value in
                TodayCalendarRow(value: value, timeZone: snapshot.timeZone)
                    .opensCalendarEvent(value.event)
                    .calendarDropTarget(value.event, enabled: acceptsTaskDrops)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var hourRuler: some View {
        GeometryReader { geometry in
            let ticks = snapshot.day.map { hours.ticks(on: $0, timeZone: snapshot.timeZone, maximumCount: max(2, Int(geometry.size.width / (labelSize * 3)))) } ?? []
            ForEach(ticks, id: \.hour) { tick in
                Text(String(tick.hour)).font(.system(size: labelSize)).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .position(x: min(geometry.size.width - labelSize, max(labelSize, tick.position * geometry.size.width)), y: labelSize * 0.7)
            }
        }
        .frame(height: labelSize * 1.4)
        .accessibilityHidden(true)
    }

    private var nowMarker: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            if let window = overview.window, window.start <= context.date, context.date < window.end {
                GeometryReader { geometry in
                    Rectangle().fill(.secondary.opacity(0.25)).frame(width: 1)
                        .offset(x: context.date.timeIntervalSince(window.start) / window.duration * geometry.size.width)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private extension View {
    func opensCalendarEvent(_ event: CalendarEventSnapshot) -> some View {
        modifier(CalendarEventLink(event: event))
    }

    func calendarDropTarget(_ event: CalendarEventSnapshot, enabled: Bool) -> some View {
        background {
            if enabled {
                GeometryReader { geometry in
                    Color.clear.preference(key: TaskCalendarDropTargetsKey.self,
                        value: [TaskCalendarDropTarget(event: event, bounds: geometry.frame(in: .global))])
                }
            }
        }
    }
}

private struct CalendarEventLink: ViewModifier {
    @Environment(\.openURL) private var openURL
    let event: CalendarEventSnapshot

    func body(content: Content) -> some View {
        Button {
            let parts = event.eventID.split(separator: ":", maxSplits: 1)
            let item = parts.last.map(String.init) ?? event.eventID
            var link = URLComponents()
            link.scheme = "x-apple-calevent"
            link.host = parts.count == 2 ? String(parts[0]) : event.calendarID
            if let url = link.url?.appending(component: item) { openURL(url) }
        } label: {
            content.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct CalendarOverviewLayout: Layout {
    let items: [CalendarOverviewItem]

    private func arrangement(width: CGFloat, subviews: Subviews) -> CalendarOverviewArrangement {
        let labels = items.indices.map { index in
            let label = subviews[index * 2]
            let ideal = label.sizeThatFits(.unspecified)
            let size = label.sizeThatFits(ProposedViewSize(width: min(ideal.width, width), height: nil))
            return CalendarOverviewLabel(start: items[index].start, end: items[index].end, width: size.width, height: size.height)
        }
        return CalendarOverviewArrangement(labels: labels, width: width)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = max(2, proposal.width ?? 320)
        return CGSize(width: width, height: arrangement(width: width, subviews: subviews).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let plan = arrangement(width: bounds.width, subviews: subviews)
        for (index, placement) in plan.placements.enumerated() {
            subviews[index * 2].place(at: CGPoint(x: bounds.minX + placement.x, y: bounds.minY + placement.y), anchor: .topLeading, proposal: ProposedViewSize(width: placement.width, height: placement.height))
            subviews[index * 2 + 1].place(at: CGPoint(x: bounds.minX + placement.barX, y: bounds.minY + placement.y + placement.height + 4), anchor: .topLeading, proposal: ProposedViewSize(width: placement.barWidth, height: 3))
        }
    }
}

extension CalendarColor {
    var swiftUIColor: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
}
