import Foundation

public struct TaskwarriorDuration: Equatable, Sendable {
    public enum Syntax: Sendable { case rawSeconds, unit, iso }
    public let rawValue: String
    public let seconds: Int64
    public let syntax: Syntax

    public init?(_ raw: String, allowRawSeconds: Bool = true) {
        rawValue = raw
        if allowRawSeconds, let value = Int64(raw), value != .min {
            seconds = value
            syntax = .rawSeconds
            return
        }
        if let unit = Self.units[raw], unit.standalone {
            seconds = unit.seconds
            syntax = .unit
            return
        }
        if let values = Self.captures(#"^([+-]?[0-9]+(?:\.[0-9]*)?)\s*([a-z]+)$"#, raw),
           let quantity = Double(values[1]), let unit = Self.units[values[2]],
           !(values[2] == "d" && quantity > 10000) {
            let value = quantity * Double(unit.seconds)
            guard value.isFinite, let result = Int64(exactly: value.rounded(.towardZero)), result != .min else { return nil }
            seconds = result
            syntax = .unit
            return
        }
        let values: [String]
        let multipliers: [Int64]
        if let components = Self.captures(#"^(-)?P(?:(\d+)Y)?(?:(\d+)M)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$"#, raw),
           components.dropFirst(2).contains(where: { !$0.isEmpty }), !raw.hasSuffix("T") {
            values = components
            multipliers = [31536000, 2592000, 86400, 3600, 60, 1]
        } else if let components = Self.captures(#"^()P(\d+)W$"#, raw) {
            values = components
            multipliers = [604800]
        } else { return nil }
        var total: Int64 = 0
        for (part, multiplier) in zip(values.dropFirst(2), multipliers) where !part.isEmpty {
            guard let quantity = Int64(part) else { return nil }
            let product = quantity.multipliedReportingOverflow(by: multiplier)
            let sum = total.addingReportingOverflow(product.partialValue)
            guard !product.overflow, !sum.overflow else { return nil }
            total = sum.partialValue
        }
        seconds = values[1].isEmpty ? total : -total
        syntax = .iso
    }

    // The pinned Duration::resolve evaluates ISO component sums as signed int32.
    var filterSeconds: Int64 {
        if case .iso = syntax { return Int64(Int32(truncatingIfNeeded: seconds)) }
        return seconds
    }

    static func captures(_ pattern: String, _ raw: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              match.range == NSRange(raw.startIndex..., in: raw) else { return nil }
        return (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: raw).map { String(raw[$0]) } ?? "" }
    }

    private static let units: [String: (seconds: Int64, standalone: Bool)] = {
        var result: [String: (Int64, Bool)] = [:]
        func add(_ seconds: Int64, _ standalone: [String], _ quantified: [String]) {
            for name in standalone { result[name] = (seconds, true) }
            for name in quantified { result[name] = (seconds, false) }
        }
        add(1, ["second", "sec"], ["seconds", "secs", "s"])
        add(60, ["minute", "min"], ["minutes", "mins"])
        add(3600, ["hour", "hr"], ["hours", "hrs", "h"])
        add(86400, ["daily", "day", "weekdays"], ["days", "d"])
        add(604800, ["weekly", "week", "wk"], ["weeks", "wks", "w"])
        add(1209600, ["biweekly", "fortnight"], ["sennight"])
        add(2592000, ["monthly", "month", "mth", "mo"], ["months", "mnths", "mths", "mos", "m"])
        add(5270400, ["bimonthly"], [])
        add(7862400, ["quarterly", "quarter", "qrtr", "qtr"], ["quarters", "qrtrs", "qtrs", "q"])
        add(15811200, ["semiannual"], [])
        add(31536000, ["yearly", "annual", "year", "yr"], ["years", "yrs", "y"])
        add(63072000, ["biannual", "biyearly"], [])
        return result
    }()
}
