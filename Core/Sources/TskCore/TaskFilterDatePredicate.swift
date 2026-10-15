import Foundation

struct FilterDatePredicate: Sendable {
    let name: String
    let operation: FilterComparison
    let operand: FilterDateExpression
    let evaluatesPattern: Bool

    init(name: String, modifier: String, value: String, quoted: Bool = false) throws {
        self.name = name
        let modifier = ["startswith", "left", "endswith", "right"].contains(modifier) ? "has" : modifier
        guard case .comparison(_, let operation, let raw) = try FilterPredicate.attribute(name, modifier: modifier, value: value) else { fatalError() }
        if case .regex(_, let inverted) = operation {
            if !quoted, let duration = TaskwarriorDuration(raw, allowRawSeconds: false) {
                operand = .empty
                evaluatesPattern = false
                self.operation = .regex(try FilterRegex(TaskAttributeValues.durationString(duration.seconds)), inverted: inverted)
            } else if !quoted, let expression = try? FilterDateExpression(raw), expression.numericVariant == nil, !raw.isEmpty {
                operand = expression
                evaluatesPattern = true
                self.operation = operation
            } else {
                operand = .empty
                evaluatesPattern = false
                if !quoted, raw.utf8.contains(where: { [43, 45, 42, 47, 94, 37].contains($0) }) {
                    throw TaskFilterError.unsupported("Quote typed regex patterns containing expression operators.")
                }
                let pattern = !quoted && !FilterScalar.isUUIDLiteral(raw) ? FilterScalar.numericOperand(raw).map { FilterScalar.number($0).text } ?? raw : raw
                self.operation = .regex(try FilterRegex(pattern), inverted: inverted)
            }
        } else {
            evaluatesPattern = false
            if FilterScalar.isUUIDLiteral(raw) { throw FilterDateExpression.invalid(raw) }
            let expression = try FilterDateExpression(raw)
            if quoted, expression.numericVariant != nil { throw FilterDateExpression.invalid(raw) }
            operand = expression
            self.operation = operation
        }
    }

    func includes(_ task: TaskRecord, context: TaskFilterContext) throws -> Bool {
        if context.schema.isUserDefined(name), let stored = task.attributes[name], !stored.isEmpty, Int64(stored) == nil {
            throw TaskFilterError.invalidStoredValue(task.id, name, .date)
        }
        let actual = FilterDateExpression.storedDate(task.attributes[name])
        let value = try operand.resolve(context)
        if actual == nil, let numeric = operand.numericVariant {
            switch operation {
            case .partial, .exact: return false
            case .notPartial, .notExact: return true
            case .less, .by: return UTF8String("") < UTF8String(numeric)
            case .greater: return false
            case .regex: break
            }
        }
        switch operation {
        case .partial, .notPartial:
            let match: Bool
            if let actual, let value { match = context.calendar.isDate(actual, inSameDayAs: value) }
            else { match = actual == nil && value == nil }
            if case .notPartial = operation { return !match }
            return match
        case .exact: return actual == value
        case .notExact: return actual != value
        case .less: return actual != nil && value != nil && actual! < value!
        case .greater: return actual != nil && value != nil && actual! > value!
        case .by: return actual == value || (actual != nil && value != nil && actual! <= value!)
        case .regex(let regex, let inverted):
            let text: String
            if let actual {
                let formatter = DateFormatter()
                formatter.calendar = context.calendar
                formatter.timeZone = context.calendar.timeZone
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                text = formatter.string(from: actual)
            } else { text = "" }
            if evaluatesPattern, let value {
                let formatter = DateFormatter()
                formatter.calendar = context.calendar
                formatter.timeZone = context.calendar.timeZone
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                return try FilterRegex(formatter.string(from: value)).matches(text) != inverted
            }
            return try regex.matches(text) != inverted
        }
    }
}
