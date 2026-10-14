import Foundation

indirect enum FilterDateExpression: Sendable {
    case empty
    case epoch(TimeInterval)
    case absolute(DateComponents, offset: Int?)
    case named(String)
    case offset(FilterDateExpression, TimeInterval)

    init(_ raw: String) throws {
        if raw.isEmpty { self = .empty; return }
        if let parts = Self.captures("^(.+)([+-])([0-9]+(?:\\.[0-9]+)?[a-z]+|P[0-9A-Z.]+)$", raw) {
            let seconds = try Self.duration(parts[3])
            self = .offset(try Self(parts[1]), parts[2] == "+" ? seconds : -seconds)
            return
        }
        if Self.captures("^-?[0-9]+$", raw) != nil, let seconds = TimeInterval(raw), seconds.isFinite, abs(seconds) <= 253402300799 {
            self = .epoch(seconds); return
        }
        if let parts = Self.captures("^([0-9]{4})-?([0-9]{2})-?([0-9]{2})(?:[T ]([0-9]{2}):?([0-9]{2})(?::?([0-9]{2}))?(Z|[+-][0-9]{2}:?[0-9]{2})?)?$", raw) {
            let values = parts.dropFirst().prefix(6).map { Int($0) ?? 0 }
            let year = values[0], month = values[1], day = values[2]
            let hour = values[3], minute = values[4], second = values[5]
            guard (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day), (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second) else { throw Self.invalid(raw) }
            let zone = parts[7]
            let offset: Int?
            if zone == "Z" { offset = 0 }
            else if !zone.isEmpty {
                let digits = zone.dropFirst().replacingOccurrences(of: ":", with: "")
                let hours = Int(digits.prefix(2))!, minutes = Int(digits.suffix(2))!
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
            if Self.captures("^[0-9]+:[0-9]{2}(?::[0-9]{2})?$", name) != nil {
                return min(nextDay, (try? resolve(context)) ?? nextDay)
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
            if let offset { calendar.timeZone = TimeZone(secondsFromGMT: offset)! }
            return calendar.date(from: components)
        case .named(let name): return try Self.named(name, context: context)
        case .offset(let base, let seconds): return try base.resolve(context)?.addingTimeInterval(seconds)
        }
    }

    static func storedDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let bytes = Array(raw.utf8.drop(while: { [9, 10, 13, 32].contains($0) }))
        let signed = bytes.first == 45 || bytes.first == 43
        let digits = bytes.dropFirst(signed ? 1 : 0).prefix { (48...57).contains($0) }
        guard !digits.isEmpty else { return nil }
        var value = UInt64(String(decoding: digits, as: UTF8.self)) ?? .max
        if bytes.first == 45 { value = 0 &- value }
        let seconds = Int64(bitPattern: value)
        return seconds == 0 ? nil : Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    static func duration(_ raw: String) throws -> TimeInterval {
        let units: [String: Double] = [
            "s": 1, "sec": 1, "secs": 1, "second": 1, "seconds": 1,
            "min": 60, "mins": 60, "minute": 60, "minutes": 60,
            "h": 3600, "hr": 3600, "hrs": 3600, "hour": 3600, "hours": 3600,
            "d": 86400, "day": 86400, "days": 86400, "daily": 86400, "weekdays": 86400,
            "w": 604800, "wk": 604800, "wks": 604800, "week": 604800, "weeks": 604800, "weekly": 604800,
            "fortnight": 1209600, "biweekly": 1209600, "sennight": 1209600,
            "m": 2592000, "mo": 2592000, "mos": 2592000, "mth": 2592000, "mths": 2592000, "mnths": 2592000, "month": 2592000, "months": 2592000, "monthly": 2592000,
            "bimonthly": 5270400, "q": 7862400, "qtr": 7862400, "qtrs": 7862400, "qrtr": 7862400, "qrtrs": 7862400, "quarter": 7862400, "quarters": 7862400, "quarterly": 7862400,
            "y": 31536000, "yr": 31536000, "yrs": 31536000, "year": 31536000, "years": 31536000, "yearly": 31536000, "annual": 31536000,
            "semiannual": 15811200, "biannual": 63072000, "biyearly": 63072000
        ]
        if let seconds = units[raw] { return seconds }
        if let parts = captures("^(-?[0-9]+(?:\\.[0-9]+)?)([a-z]+)$", raw), let quantity = Double(parts[1]), let unit = units[parts[2]] { return quantity * unit }
        if let parts = captures("^P(?:(-?[0-9]+(?:\\.[0-9]+)?)Y)?(?:(-?[0-9]+(?:\\.[0-9]+)?)M)?(?:(-?[0-9]+(?:\\.[0-9]+)?)W)?(?:(-?[0-9]+(?:\\.[0-9]+)?)D)?(?:T(?:(-?[0-9]+(?:\\.[0-9]+)?)H)?(?:(-?[0-9]+(?:\\.[0-9]+)?)M)?(?:(-?[0-9]+(?:\\.[0-9]+)?)S)?)?$", raw), parts.dropFirst().contains(where: { !$0.isEmpty }) {
            return zip(parts.dropFirst(), [31536000.0, 2592000, 604800, 86400, 3600, 60, 1]).reduce(0) { $0 + (Double($1.0) ?? 0) * $1.1 }
        }
        throw invalid(raw)
    }

    static let periodNames = Set(["sopd", "sod", "sond", "eopd", "eod", "eond", "sopw", "sow", "sonw", "eopw", "eow", "eonw", "sopww", "soww", "sonww", "eopww", "eoww", "eonww", "sopm", "som", "sonm", "eopm", "eom", "eonm", "sopq", "soq", "sonq", "eopq", "eoq", "eonq", "sopy", "soy", "sony", "eopy", "eoy", "eony"])
    static let days = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    static let months = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
    static let holidays = ["eastermonday", "easter", "ascension", "pentecost", "goodfriday", "midsommar", "midsommarafton", "juhannus"]

    private static func isNamed(_ raw: String) -> Bool {
        if raw == "now" || periodNames.contains(raw) || holidays.contains(raw) { return true }
        if ["today", "tomorrow", "yesterday", "later"].contains(where: { raw.utf8.count >= 3 && $0.hasPrefix(raw) }) { return true }
        if raw.count >= 4 && "someday".hasPrefix(raw) { return true }
        if raw.count >= 3 && (days + months).contains(where: { $0.hasPrefix(raw.lowercased()) }) { return true }
        if captures("^([1-9]|[12][0-9]|3[01])(st|nd|rd|th)$", raw) != nil { return true }
        return captures("^[0-9]{1,2}:[0-9]{2}(?::[0-9]{2})?$", raw) != nil
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
        if let parts = captures("^([0-9]+):([0-9]{2})(?::([0-9]{2}))?$", raw) {
            let hour = Int(parts[1])!, minute = Int(parts[2])!, second = Int(parts[3]) ?? 0
            guard hour <= 23, minute <= 59, second <= 59 else { throw invalid(raw) }
            let date = calendar.date(bySettingHour: hour, minute: minute, second: second, of: day)!
            return date <= context.now ? calendar.date(byAdding: .day, value: 1, to: date)! : date
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
