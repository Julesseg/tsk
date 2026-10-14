import Foundation

struct FilterDatePredicate: Sendable {
    let name: String
    let operation: FilterComparison
    let operand: FilterDateExpression

    init(name: String, modifier: String, value: String) throws {
        self.name = name
        guard case .comparison(_, let operation, let raw) = try FilterPredicate.attribute(name, modifier: modifier, value: value) else { fatalError() }
        self.operation = operation
        if case .regex = operation { operand = .empty }
        else { operand = try FilterDateExpression(raw) }
    }

    func includes(_ task: TaskRecord, context: TaskFilterContext) throws -> Bool {
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
            return try regex.matches(text) != inverted
        }
    }
}
