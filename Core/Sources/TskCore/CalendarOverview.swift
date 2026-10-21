import Foundation

public struct CalendarDisplayHours: Codable, Equatable, Sendable {
    public let startHour: Int
    public let endHour: Int

    public init(startHour: Int = 8, endHour: Int = 18) {
        if (0...23).contains(startHour), (1...24).contains(endHour), startHour < endHour {
            self.startHour = startHour; self.endHour = endHour
        } else { self.startHour = 8; self.endHour = 18 }
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(startHour: try values.decode(Int.self, forKey: .startHour), endHour: try values.decode(Int.self, forKey: .endHour))
    }

    public func window(on day: DateInterval, timeZone: TimeZone) -> DateInterval? {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        guard let start = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: day.start),
              let end = endHour == 24 ? day.end : calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: day.start),
              start < end else { return nil }
        return DateInterval(start: start, end: end)
    }

    public func tickHours(maximumCount: Int) -> [Int] {
        let step = max(1, Int(ceil(Double(endHour - startHour) / Double(max(1, maximumCount - 1)))))
        var ticks = Array(stride(from: startHour, to: endHour, by: step))
        ticks.append(endHour)
        return ticks
    }

    public func ticks(on day: DateInterval, timeZone: TimeZone, maximumCount: Int) -> [CalendarOverviewTick] {
        guard let window = window(on: day, timeZone: timeZone) else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return tickHours(maximumCount: maximumCount).compactMap { hour in
            if hour == 24 { return CalendarOverviewTick(hour: hour, position: 1) }
            guard let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day.start),
                  calendar.component(.hour, from: date) == hour,
                  window.start <= date, date <= window.end else { return nil }
            return CalendarOverviewTick(hour: hour, position: date.timeIntervalSince(window.start) / window.duration)
        }
    }
}

public struct CalendarOverviewTick: Sendable {
    public let hour: Int
    public let position: Double
}

public struct CalendarOverviewItem: Identifiable, Sendable {
    public let value: TodayCalendarEvent
    public let start: Double
    public let end: Double
    public var id: CalendarEventIdentity { value.id }
}

public struct CalendarOverview: Sendable {
    public let window: DateInterval?
    public let allDay: [TodayCalendarEvent]
    public let outsideHours: [TodayCalendarEvent]
    public let items: [CalendarOverviewItem]

    public init(snapshot: TodayCalendarSnapshot, hours: CalendarDisplayHours) {
        window = snapshot.day.flatMap { hours.window(on: $0, timeZone: snapshot.timeZone) }
        allDay = snapshot.events.filter { $0.event.isAllDay }
        var outside: [TodayCalendarEvent] = []
        var timed: [CalendarOverviewItem] = []
        for value in snapshot.events where !value.event.isAllDay {
            guard let window,
                  value.isInstant ? window.start <= value.visibleStart && value.visibleStart < window.end : value.visibleStart < window.end && value.visibleEnd > window.start else {
                outside.append(value); continue
            }
            timed.append(CalendarOverviewItem(value: value,
                start: max(0, value.visibleStart.timeIntervalSince(window.start) / window.duration),
                end: min(1, value.visibleEnd.timeIntervalSince(window.start) / window.duration)))
        }
        outsideHours = outside; items = timed
    }
}

public struct CalendarOverviewLabel: Sendable {
    public let start: Double
    public let end: Double
    public let width: Double
    public let height: Double
    public init(start: Double, end: Double, width: Double, height: Double) {
        self.start = start; self.end = end; self.width = width; self.height = height
    }
}

public struct CalendarOverviewPlacement: Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let barX: Double
    public let barWidth: Double
}

public struct CalendarOverviewArrangement: Sendable {
    public let placements: [CalendarOverviewPlacement]
    public let height: Double

    public init(labels: [CalendarOverviewLabel], width: Double, spacing: Double = 8) {
        let width = max(2, width.isFinite ? width : 2)
        var laneEnds: [Double] = []
        var laneHeights: [Double] = []
        var entries: [(CalendarOverviewLabel, Int, Double, Double, Double, Double)] = []
        for label in labels {
            let labelWidth = min(width, max(0, label.width))
            let barX = min(width - 2, max(0, label.start * width))
            let barWidth = min(width - barX, max(2, (label.end - label.start) * width))
            let x = min(barX, width - labelWidth)
            let right = max(x + labelWidth, barX + barWidth)
            let lane = laneEnds.firstIndex(where: { $0 + spacing <= x }) ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(right); laneHeights.append(label.height + 7) }
            else { laneEnds[lane] = right; laneHeights[lane] = max(laneHeights[lane], label.height + 7) }
            entries.append((label, lane, x, labelWidth, barX, barWidth))
        }
        var offsets: [Double] = []; var top = 0.0
        for height in laneHeights { offsets.append(top); top += height + spacing }
        placements = entries.map { label, lane, x, labelWidth, barX, barWidth in
            CalendarOverviewPlacement(x: x, y: offsets[lane], width: labelWidth, height: label.height, barX: barX, barWidth: barWidth)
        }
        height = max(0, top - spacing)
    }
}
