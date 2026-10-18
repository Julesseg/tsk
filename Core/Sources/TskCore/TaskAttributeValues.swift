import Foundation

public enum TaskAttributeValues {
    public static func normalized(_ value: String, for definition: TaskAttributeDefinition) throws -> String? {
        guard !value.isEmpty else { return nil }
        switch definition.type {
        case .string:
            guard definition.values.map({ $0.contains(where: { $0.matchesBytes(value) }) }) ?? true else {
                throw invalid(definition, "Choose one of the configured allowed values or clear the field.")
            }
            return value
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
                throw invalid(definition, "Choose a date or enter Unix seconds or a valid ISO 8601 timestamp. Use a real calendar day, hours 00–23, and minutes/seconds 00–59.")
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
        let extended = #"^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?(Z|[+-]\d{2}:?\d{2})$"#
        let compact = #"^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(?:\.(\d+))?(Z|[+-]\d{2}:?\d{2})$"#
        guard let parts = TaskwarriorDuration.captures(extended, raw) ?? TaskwarriorDuration.captures(compact, raw),
              let year = Int(parts[1]), let month = Int(parts[2]), let day = Int(parts[3]),
              let hour = Int(parts[4]), let minute = Int(parts[5]), let second = Int(parts[6]),
              (1...12).contains(month), (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let monthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let days = calendar.range(of: .day, in: .month, for: monthStart), days.contains(day),
              let midnight = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let components = calendar.dateComponents([.year, .month, .day], from: midnight)
        guard components.year == year, components.month == month, components.day == day else { return nil }
        var offset = 0
        if parts[8] != "Z" {
            let sign = parts[8].hasPrefix("-") ? -1 : 1
            let digits = parts[8].dropFirst().filter { $0 != ":" }
            guard let hours = Int(digits.prefix(2)), let minutes = Int(digits.suffix(2)),
                  (0...23).contains(hours), (0...59).contains(minutes) else { return nil }
            offset = sign * (hours * 3600 + minutes * 60)
        }
        let fraction = parts[7].isEmpty ? 0 : Double("0." + parts[7]) ?? 0
        let seconds = midnight.timeIntervalSince1970 + Double(hour * 3600 + minute * 60 + second - offset) + fraction
        guard seconds.isFinite, abs(seconds) <= 253402300799 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    public static func durationSeconds(_ raw: String) -> Int64? {
        TaskwarriorDuration(raw)?.seconds
    }

    static func durationString(_ seconds: Int64) -> String {
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
