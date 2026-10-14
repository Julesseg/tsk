import Foundation

public extension TaskRecord {
    var plannedDate: Date? { dateAttribute("scheduled") }
    var deadline: Date? { dateAttribute("due") }
    var startedAt: Date? { dateAttribute("start") }

    func isInToday(at now: Date, calendar: Calendar) -> Bool {
        guard status == "pending", let day = calendar.dateInterval(of: .day, for: now) else { return false }
        return [plannedDate, deadline].compactMap { $0 }.contains { $0 < day.end }
    }

    private func dateAttribute(_ name: String) -> Date? {
        planningDate(attributes[name])
    }
}

public extension TaskDraft {
    var plannedDate: Date? {
        get { planningDate(attributes["scheduled"]) }
        set { attributes["scheduled"] = newValue.map { String(Int($0.timeIntervalSince1970)) } }
    }

    var deadline: Date? {
        get { planningDate(attributes["due"]) }
        set { attributes["due"] = newValue.map { String(Int($0.timeIntervalSince1970)) } }
    }
}

private func planningDate(_ raw: String?) -> Date? {
    guard let raw, let seconds = TimeInterval(raw), seconds.isFinite,
          abs(seconds) <= 253402300799 else { return nil }
    return Date(timeIntervalSince1970: seconds)
}
