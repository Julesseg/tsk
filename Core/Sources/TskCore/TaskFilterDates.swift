import Foundation

indirect enum FilterDateExpression: Sendable {
    case empty
    case epoch(TimeInterval)
    case absolute(DateComponents, offset: Int?)
    case named(String)
    case offset(FilterDateExpression, TimeInterval)

    init(_ raw: String) throws {
        if raw.isEmpty { self = .empty; return }
        if Self.captures("^-?[0-9]+$", raw) != nil, let seconds = TimeInterval(raw), seconds.isFinite, abs(seconds) <= 253402300799 {
            self = .epoch(seconds); return
        }
        if let parts = Self.captures("^([0-9]{4})-?([0-9]{2})-?([0-9]{2})(?:[T ]([0-9]{2}):?([0-9]{2})(?::?([0-9]{2}))?(Z|[+-][0-9]{2}(?::?[0-9]{2})?)?)?$", raw) {
            let values = parts.dropFirst().prefix(6).map { Int($0) ?? 0 }
            let year = values[0], month = values[1], day = values[2]
            let hour = values[3], minute = values[4], second = values[5]
            guard (1900...9999).contains(year), (1...12).contains(month), (1...31).contains(day), (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second) else { throw Self.invalid(raw) }
            let zone = parts[7]
            let offset: Int?
            if zone == "Z" { offset = 0 }
            else if !zone.isEmpty {
                let digits = zone.dropFirst().replacingOccurrences(of: ":", with: "")
                let hours = Int(digits.prefix(2))!, minutes = digits.count == 2 ? 0 : Int(digits.suffix(2))!
                guard hours <= 23, minutes <= 59 else { throw Self.invalid(raw) }
                offset = (hours * 3600 + minutes * 60) * (zone.first == "+" ? 1 : -1)
            } else { offset = nil }
            let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(secondsFromGMT: 0)!
            guard let date = utc.date(from: components), utc.dateComponents([.year, .month, .day], from: date).year == year,
                  utc.component(.month, from: date) == month, utc.component(.day, from: date) == day else { throw Self.invalid(raw) }
            self = .absolute(components, offset: offset); return
        }
        if let components = Self.alternateDate(raw) { self = .absolute(components, offset: nil); return }
        let bytes = Array(raw.utf8)
        for index in bytes.indices.reversed() where index > 0 && (bytes[index] == 43 || bytes[index] == 45) {
            let suffix = String(decoding: bytes[(index + 1)...], as: UTF8.self)
            let prefix = String(decoding: bytes[..<index], as: UTF8.self)
            if let duration = TaskwarriorDuration(suffix), let base = try? Self(prefix) {
                self = .offset(base, TimeInterval(duration.seconds) * (bytes[index] == 43 ? 1 : -1))
                return
            }
        }
        if Self.isNamed(raw) {
            if let parts = Self.captures("^([0-9]+)(st|nd|rd|th)$", raw), let ordinal = Int(parts[1]) {
                let expected = (11...13).contains(ordinal % 100) ? "th" : ordinal % 10 == 1 ? "st" : ordinal % 10 == 2 ? "nd" : ordinal % 10 == 3 ? "rd" : "th"
                guard parts[2] == expected else { throw Self.invalid(raw) }
            }
            if let parts = Self.captures("^([0-9]+):([0-9]{2})(?::([0-9]{2}))?$", raw) {
                guard Int(parts[1])! <= 23, Int(parts[2])! <= 59, (Int(parts[3]) ?? 0) <= 59 else { throw Self.invalid(raw) }
            }
            self = .named(raw); return
        }
        if let seconds = try? Self.duration(raw) { self = .offset(.named("now"), seconds); return }
        if Self.captures("^-?[0-9]+(?:\\.[0-9]+)?[a-z]+$", raw) != nil || raw.hasPrefix("P") {
            self = .offset(.named("now"), try Self.duration(raw)); return
        }
        throw Self.invalid(raw)
    }

    var numericVariant: String? {
        if case .epoch(let seconds) = self, seconds < 315532800 || seconds >= 253402293599 { return String(Int64(seconds)) }
        return nil
    }

    func nextEvaluation(context: TaskFilterContext) -> Date? {
        switch self {
        case .empty, .epoch, .absolute: return nil
        case .offset(let base, _): return base.nextEvaluation(context: context)
        case .named(let name):
            if name == "now" { return context.now.addingTimeInterval(1) }
            if (name.count >= 3 && "later".hasPrefix(name)) || (name.count >= 4 && "someday".hasPrefix(name)) { return nil }
            let nextDay = context.calendar.date(byAdding: .day, value: 1, to: context.calendar.startOfDay(for: context.now))!
            if Self.informalTime(name) != nil {
                return min(nextDay, ((try? resolve(context)) ?? nextDay).addingTimeInterval(1))
            }
            if Self.holidays.contains(name) {
                let boundary = Self.holiday(name.hasPrefix("mid") || name == "juhannus" ? name : "easter", context: context).addingTimeInterval(1)
                return min(nextDay, boundary)
            }
            return nextDay
        }
    }

    func resolve(_ context: TaskFilterContext) throws -> Date? {
        switch self {
        case .empty: return nil
        case .epoch(let seconds): return Date(timeIntervalSince1970: seconds)
        case .absolute(let components, let offset):
            var calendar = context.calendar
            if let offset {
                calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                return calendar.date(from: components)?.addingTimeInterval(TimeInterval(-offset))
            }
            return calendar.date(from: components)
        case .named(let name): return try Self.named(name, context: context)
        case .offset(let base, let seconds): return try base.resolve(context)?.addingTimeInterval(seconds)
        }
    }

    static func storedDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let bytes = Array(raw.utf8.drop(while: { [9, 10, 11, 12, 13, 32].contains($0) }))
        let signed = bytes.first == 45 || bytes.first == 43
        let digits = bytes.dropFirst(signed ? 1 : 0).prefix { (48...57).contains($0) }
        guard !digits.isEmpty else { return nil }
        let parsed = UInt64(String(decoding: digits, as: UTF8.self))
        var value = parsed ?? .max
        if parsed != nil, bytes.first == 45 { value = 0 &- value }
        let seconds = Int64(bitPattern: value)
        return seconds == 0 ? nil : Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    static func duration(_ raw: String) throws -> TimeInterval {
        guard let duration = TaskwarriorDuration(raw) else { throw invalid(raw) }
        return TimeInterval(duration.seconds)
    }

    static let periodNames = Set(["sopd", "sod", "sond", "eopd", "eod", "eond", "sopw", "sow", "sonw", "eopw", "eow", "eonw", "sopww", "soww", "sonww", "eopww", "eoww", "eonww", "sopm", "som", "sonm", "eopm", "eom", "eonm", "sopq", "soq", "sonq", "eopq", "eoq", "eonq", "sopy", "soy", "sony", "eopy", "eoy", "eony"])
    static let days = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    static let months = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
    static let holidays = ["eastermonday", "easter", "ascension", "pentecost", "goodfriday", "midsommar", "midsommarafton", "juhannus"]

    private static func informalTime(_ raw: String) -> (Int, Int, Int)? {
        guard let parts = captures("^([0-9]{1,2})(?::([0-9]{2})(?::([0-9]+))?)?(am|a|pm|p)?$", raw),
              !parts[2].isEmpty || !parts[4].isEmpty,
              var hour = Int(parts[1]), let minute = Int(parts[2].isEmpty ? "0" : parts[2]),
              let second = Int(parts[3].isEmpty ? "0" : parts[3]) else { return nil }
        if parts[4].hasPrefix("a"), hour == 12 { hour = 0 }
        if parts[4].hasPrefix("p"), hour != 12 { hour += 12 }
        guard hour < 24, minute < 60, second < 60 else { return nil }
        return (hour, minute, second)
    }

    private static func alternateDate(_ raw: String) -> DateComponents? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        if let parts = captures("^([0-9]{4})-([0-9]{2})$", raw), let year = Int(parts[1]), let month = Int(parts[2]), (1900...9999).contains(year), (1...12).contains(month) {
            return DateComponents(year: year, month: month, day: 1)
        }
        if let parts = captures("^([0-9]{4})-([0-9]{3})$", raw), let year = Int(parts[1]), let ordinal = Int(parts[2]), (1900...9999).contains(year), (1...366).contains(ordinal),
           let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)), let date = calendar.date(byAdding: .day, value: ordinal - 1, to: start), calendar.component(.year, from: date) == year {
            return calendar.dateComponents([.year, .month, .day], from: date)
        }
        if let parts = captures("^([0-9]{4})-W([0-9]{2})(?:-([0-9]))?$", raw), let year = Int(parts[1]), let week = Int(parts[2]), (1900...9999).contains(year), (1...53).contains(week),
           let weekday = Int(parts[3].isEmpty ? "0" : parts[3]), (0...6).contains(weekday),
           let jan4 = calendar.date(from: DateComponents(year: year, month: 1, day: 4)), let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
           let date = calendar.date(byAdding: .day, value: week * 7 + weekday - (calendar.component(.weekday, from: jan4) - 1) - 4, to: start) {
            return calendar.dateComponents([.year, .month, .day], from: date)
        }
        return nil
    }

    private static func isNamed(_ raw: String) -> Bool {
        if raw == "now" || periodNames.contains(raw) || holidays.contains(raw) { return true }
        if ["today", "tomorrow", "yesterday", "later"].contains(where: { raw.utf8.count >= 3 && $0.hasPrefix(raw) }) { return true }
        if raw.count >= 4 && "someday".hasPrefix(raw) { return true }
        if raw.count >= 3 && (days + months).contains(where: { $0.hasPrefix(raw.lowercased()) }) { return true }
        if captures("^([1-9]|[12][0-9]|3[01])(st|nd|rd|th)$", raw) != nil { return true }
        return informalTime(raw) != nil
    }

    static func named(_ raw: String, context: TaskFilterContext) throws -> Date {
        let calendar = context.calendar
        let day = calendar.startOfDay(for: context.now)
        if raw == "now" { return context.now }
        if raw == "sod" || (raw.count >= 3 && "today".hasPrefix(raw)) { return day }
        if raw == "sopd" || (raw.count >= 3 && "yesterday".hasPrefix(raw)) { return calendar.date(byAdding: .day, value: -1, to: day)! }
        if raw == "sond" || (raw.count >= 3 && "tomorrow".hasPrefix(raw)) { return calendar.date(byAdding: .day, value: 1, to: day)! }
        if (raw.count >= 3 && "later".hasPrefix(raw)) || (raw.count >= 4 && "someday".hasPrefix(raw)) { return calendar.date(from: DateComponents(year: 9999, month: 12, day: 30))! }
        if raw.hasSuffix("d"), ["eopd", "eod", "eond"].contains(raw) {
            return calendar.date(byAdding: .day, value: raw == "eopd" ? 0 : raw == "eod" ? 1 : 2, to: day)!.addingTimeInterval(-1)
        }
        if periodNames.contains(raw) { return period(raw, context: context) }
        if let index = days.firstIndex(where: { $0.hasPrefix(raw.lowercased()) }) {
            let distance = (index - (calendar.component(.weekday, from: day) - 1) + 7) % 7
            return calendar.date(byAdding: .day, value: distance == 0 ? 7 : distance, to: day)!
        }
        if let index = months.firstIndex(where: { $0.hasPrefix(raw.lowercased()) }) {
            let year = calendar.component(.year, from: day) + (calendar.component(.month, from: day) >= index + 1 ? 1 : 0)
            return calendar.date(from: DateComponents(year: year, month: index + 1, day: 1))!
        }
        if let parts = captures("^([0-9]+)(st|nd|rd|th)$", raw), let ordinal = Int(parts[1]) {
            let expected = (11...13).contains(ordinal % 100) ? "th" : ordinal % 10 == 1 ? "st" : ordinal % 10 == 2 ? "nd" : ordinal % 10 == 3 ? "rd" : "th"
            guard parts[2] == expected else { throw invalid(raw) }
            let month = calendar.date(from: calendar.dateComponents([.year, .month], from: day))!
            let base = calendar.date(byAdding: .month, value: ordinal <= calendar.component(.day, from: day) ? 1 : 0, to: month)!
            return calendar.date(byAdding: .day, value: ordinal - 1, to: base)!
        }
        if let (hour, minute, second) = informalTime(raw) {
            let date = calendar.date(bySettingHour: hour, minute: minute, second: second, of: day)!
            return date < context.now ? calendar.date(byAdding: .day, value: 1, to: date)! : date
        }
        if holidays.contains(raw) { return holiday(raw, context: context) }
        throw invalid(raw)
    }

    static func period(_ name: String, context: TaskFilterContext) -> Date {
        let calendar = context.calendar
        let day = calendar.startOfDay(for: context.now)
        let end = name.hasPrefix("e")
        let shift = name.contains("op") ? -1 : name.contains("on") ? 1 : 0
        let unit = name.hasSuffix("ww") ? "ww" : String(name.suffix(1))
        let start: Date
        let next: Date
        switch unit {
        case "w", "ww":
            let distance = unit == "ww" ? calendar.component(.weekday, from: day) - 2 : (calendar.component(.weekday, from: day) + 5) % 7
            let monday = calendar.date(byAdding: .day, value: -distance + shift * 7, to: day)!
            start = monday
            next = calendar.date(byAdding: .day, value: unit == "ww" ? 5 : 7, to: monday)!
        case "m":
            let month = calendar.date(from: calendar.dateComponents([.year, .month], from: day))!
            start = calendar.date(byAdding: .month, value: shift, to: month)!
            next = calendar.date(byAdding: .month, value: 1, to: start)!
        case "q":
            let year = calendar.component(.year, from: day), month = calendar.component(.month, from: day)
            let quarter = calendar.date(from: DateComponents(year: year, month: ((month - 1) / 3) * 3 + 1, day: 1))!
            start = calendar.date(byAdding: .month, value: shift * 3, to: quarter)!
            next = calendar.date(byAdding: .month, value: 3, to: start)!
        default:
            let year = calendar.component(.year, from: day) + shift
            start = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
            next = calendar.date(byAdding: .year, value: 1, to: start)!
        }
        return end ? next.addingTimeInterval(-1) : start
    }

    private static func holiday(_ name: String, context: TaskFilterContext) -> Date {
        let calendar = context.calendar
        let year = calendar.component(.year, from: context.now)
        func date(_ year: Int) -> Date {
            if name.hasPrefix("mid") || name == "juhannus" {
                let base = calendar.date(from: DateComponents(year: year, month: 6, day: name == "midsommar" ? 20 : 19))!
                let weekday = name == "midsommar" ? 7 : 6
                return calendar.date(byAdding: .day, value: weekday - calendar.component(.weekday, from: base), to: base)!
            }
            let a = year % 19, b = year / 100, c = year % 100
            let d = b / 4, e = b % 4, f = (b + 8) / 25, g = (b - f + 1) / 3
            let h = (19 * a + b - d - g + 15) % 30, i = c / 4, k = c % 4
            let l = (32 + 2 * e + 2 * i - h - k) % 7, m = (a + 11 * h + 22 * l) / 451
            let n = h + l - 7 * m + 114
            let easter = calendar.date(from: DateComponents(year: year, month: n / 31, day: n % 31 + 1))!
            return easter
        }
        let current = date(year)
        let base = current < context.now ? date(year + 1) : current
        let offset = name == "eastermonday" ? 1 : name == "ascension" ? 39 : name == "pentecost" ? 49 : name == "goodfriday" ? -2 : 0
        return calendar.date(byAdding: .day, value: offset, to: base)!
    }

    static func captures(_ pattern: String, _ value: String) -> [String]? {
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(value.startIndex..., in: value)
        guard let match = regex.firstMatch(in: value, range: range), match.range == range else { return nil }
        return (0..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: value) else { return "" }
            return String(value[range])
        }
    }

    static func invalid(_ value: String) -> TaskFilterError { .syntax("Invalid date operand ‘\(value)’.", byteOffset: 0) }
}
