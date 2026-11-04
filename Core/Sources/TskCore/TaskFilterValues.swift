import Foundation

enum TaskFilterValue {
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

    static func uuidIsValid(_ raw: String) -> Bool {
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
}
