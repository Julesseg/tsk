import Foundation

public enum TaskAttributeValues {
    public static func normalized(_ value: String, for definition: TaskAttributeDefinition) throws -> String? {
        guard !value.isEmpty else { return nil }
        switch definition.type {
        case .string: return value
        case .numeric:
            guard value.range(of: #"^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil,
                  let number = Double(value), number.isFinite else {
                throw invalid(definition, "Enter a finite number, such as -1.25 or 1e2.")
            }
            var result = String(number)
            if result.hasSuffix(".0") { result.removeLast(2) }
            return result
        case .date:
            guard let date = date(value), let seconds = Int64(exactly: date.timeIntervalSince1970.rounded(.towardZero)) else {
                throw invalid(definition, "Choose a date or enter Unix seconds or an ISO 8601 timestamp.")
            }
            return String(seconds)
        case .duration:
            guard let seconds = durationSeconds(value) else { throw invalid(definition, "Enter a duration such as 2h, -30min, or P1DT30M.") }
            return durationString(seconds)
        case .uuid:
            guard uuidIsValid(value) else { throw invalid(definition, "Enter a UUID or a Taskwarrior UUID prefix of at least eight hexadecimal characters.") }
            return value
        }
    }

    public static func date(_ raw: String) -> Date? {
        if let seconds = Int64(raw), abs(Double(seconds)) <= 253402300799 { return Date(timeIntervalSince1970: Double(seconds)) }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: raw), abs(date.timeIntervalSince1970) <= 253402300799 { return date }
        formatter.formatOptions.insert(.withFractionalSeconds)
        if let date = formatter.date(from: raw), abs(date.timeIntervalSince1970) <= 253402300799 { return date }
        let compact = DateFormatter()
        compact.locale = Locale(identifier: "en_US_POSIX")
        compact.calendar = Calendar(identifier: .gregorian)
        compact.timeZone = TimeZone(secondsFromGMT: 0)
        compact.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        compact.isLenient = false
        guard let date = compact.date(from: raw), compact.string(from: date).matchesBytes(raw) else { return nil }
        return date
    }

    public static func durationSeconds(_ raw: String) -> Int64? {
        if let seconds = Int64(raw), seconds != .min { return seconds }
        let pattern = #"^(-)?P(?:(\d+)Y)?(?:(\d+)M)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$"#
        if let match = try? NSRegularExpression(pattern: pattern).firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)) {
            let source = raw as NSString
            var total: Int64 = 0
            var parts = 0
            for (group, unit) in [(2, Int64(31536000)), (3, 2592000), (4, 86400), (5, 3600), (6, 60), (7, 1)] where match.range(at: group).location != NSNotFound {
                guard let amount = Int64(source.substring(with: match.range(at: group))) else { return nil }
                let product = amount.multipliedReportingOverflow(by: unit)
                let sum = total.addingReportingOverflow(product.partialValue)
                guard !product.overflow, !sum.overflow else { return nil }
                total = sum.partialValue
                parts += 1
            }
            guard parts > 0, !raw.hasSuffix("T") else { return nil }
            return match.range(at: 1).location == NSNotFound ? total : -total
        }
        if let match = try? NSRegularExpression(pattern: #"^(-)?P(\d+)W$"#).firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
           let weeks = Int64((raw as NSString).substring(with: match.range(at: 2))) {
            let result = weeks.multipliedReportingOverflow(by: 604800)
            guard !result.overflow else { return nil }
            return match.range(at: 1).location == NSNotFound ? result.partialValue : -result.partialValue
        }
        let units: [String: Int64] = ["s": 1, "sec": 1, "secs": 1, "second": 1, "seconds": 1, "min": 60, "mins": 60, "minute": 60, "minutes": 60, "h": 3600, "hr": 3600, "hrs": 3600, "hour": 3600, "hours": 3600, "d": 86400, "day": 86400, "days": 86400, "w": 604800, "wk": 604800, "wks": 604800, "week": 604800, "weeks": 604800, "m": 2592000, "mo": 2592000, "month": 2592000, "months": 2592000, "y": 31536000, "yr": 31536000, "year": 31536000, "years": 31536000]
        guard let match = try? NSRegularExpression(pattern: #"^(-?(?:[0-9]+(?:\.[0-9]+)?|\.[0-9]+))\s?([a-z]+)$"#).firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let number = Double((raw as NSString).substring(with: match.range(at: 1))),
              let unit = units[(raw as NSString).substring(with: match.range(at: 2))] else { return nil }
        let seconds = number * Double(unit)
        guard seconds.isFinite, let result = Int64(exactly: seconds.rounded(.towardZero)), result != .min else { return nil }
        return result
    }

    private static func durationString(_ seconds: Int64) -> String {
        guard seconds != 0 else { return "PT0S" }
        let magnitude = abs(seconds)
        let days = magnitude / 86400
        let hours = magnitude % 86400 / 3600
        let minutes = magnitude % 3600 / 60
        let remainder = magnitude % 60
        var value = seconds < 0 ? "-P" : "P"
        if days != 0 { value += "\(days)D" }
        if hours != 0 || minutes != 0 || remainder != 0 {
            value += "T"
            if hours != 0 { value += "\(hours)H" }
            if minutes != 0 { value += "\(minutes)M" }
            if remainder != 0 { value += "\(remainder)S" }
        }
        return value
    }

    private static func uuidIsValid(_ raw: String) -> Bool {
        let bytes = Array(raw.utf8)
        let pattern = Array("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx".utf8)
        var index = 0
        while index < min(bytes.count, pattern.count) {
            let byte = bytes[index]
            if pattern[index] == 120 {
                guard (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte) else { break }
            } else if byte != 45 { break }
            index += 1
        }
        guard index >= 8 else { return false }
        if index == bytes.count { return true }
        let following = String(decoding: bytes.dropFirst(index), as: UTF8.self).unicodeScalars.first
        return following.map { CharacterSet.whitespacesAndNewlines.contains($0) || "+-*/()<>^!%=~".unicodeScalars.contains($0) } ?? false
    }

    private static func invalid(_ definition: TaskAttributeDefinition, _ guidance: String) -> TaskAttributeError {
        .invalidValue(definition.name.rawValue, definition.type, guidance)
    }
}

extension TaskManager {
    func normalizedUserAttributes(_ changes: TaskAttributePatch, requireDefinitions: Bool = false) async throws -> TaskAttributePatch {
        if requireDefinitions, userAttributeDefinitions == nil { throw TaskAttributeError.storageNotConfigured }
        let definitions = try await userAttributeDefinitions?.load() ?? []
        let byName = Dictionary(definitions.map { ($0.name, $0) }, uniquingKeysWith: { _, new in new })
        var result = changes
        for (name, value) in changes {
            guard let definition = byName[UTF8String(name)] else {
                if requireDefinitions { throw TaskAttributeError.missingDefinition(name) }
                continue
            }
            result.updateValue(try value.flatMap { try TaskAttributeValues.normalized($0, for: definition) }, forKey: name)
        }
        return result
    }

    public func updateUserAttributes(id: UUID, changes: TaskAttributePatch) async throws -> TaskRecord {
        let lease = try await beginMutation()
        defer { endMutation(lease) }
        return try await updateTask(id: id, changes: changes, userAttributesOnly: true)
    }
}
