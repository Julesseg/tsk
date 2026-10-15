import Foundation

indirect enum TaskValueExpression: Sendable {
    case literal(TaskExpressionValue)
    case identity([String])
    case field(String)
    case date(FilterDateExpression)
    case predicate(FilterPredicate)
    case unary(String, TaskValueExpression)
    case binary(String, TaskValueExpression, TaskValueExpression)

    func value(_ task: TaskRecord, _ context: TaskFilterContext) throws -> TaskExpressionValue {
        switch self {
        case .literal(let value): return value
        case .identity(let prefixes): return .boolean(prefixes.contains { task.id.uuidString.lowercased().utf8.starts(with: $0.utf8) })
        case .field(let name): return try TaskExpressionValue.field(name, task: task, context: context)
        case .date(let expression): return .date(try expression.resolve(context)?.timeIntervalSince1970 ?? 0)
        case .predicate(let predicate): return .boolean(try predicate.includes(task, context: context))
        case .unary(let op, let child):
            let value = try child.value(task, context)
            if op == "!" { return .boolean(!value.boolean) }
            if op == "+" { return value }
            return try TaskExpressionValue.integer(0).applying("-", value, context: context)
        case .binary(let op, let left, let right):
            let lhs = try left.value(task, context)
            let rhs = try right.value(task, context)
            if op == "~" || op == "!~", left.sourceName == "description" {
                let regex = try FilterRegex(TaskExpressionValue.dequoted(rhs.text(context)))
                var matches = try regex.matches(TaskExpressionValue.dequoted(lhs.text(context)))
                for (key, note) in task.attributes where !matches && key.utf8.starts(with: "annotation_".utf8) {
                    matches = try regex.matches(note)
                }
                return .boolean(matches != (op == "!~"))
            }
            let name = left.sourceName
            return try lhs.applying(op, rhs, context: context, field: name)
        }
    }

    private var sourceName: String? {
        switch self {
        case .field(let name): name
        case .unary("+", let child): child.sourceName
        case .binary(let op, let left, _) where ["+", "-", "*", "/", "%", "^"].contains(op): left.sourceName
        default: nil
        }
    }

    var hasActiveTag: Bool {
        switch self {
        case .predicate(.virtualTag(.active, let required)): required
        case .unary(_, let child): child.hasActiveTag
        case .binary(_, let left, let right): left.hasActiveTag || right.hasActiveTag
        default: false
        }
    }

    var disablesWorkingSet: Bool {
        switch self {
        case .identity: true
        case .binary(let op, let left, let right): op == "or" || op == "xor" || op == "||" || left.disablesWorkingSet || right.disablesWorkingSet
        case .unary(_, let child): child.disablesWorkingSet
        default: false
        }
    }

    func nextEvaluation(context: TaskFilterContext) -> Date? {
        switch self {
        case .literal, .identity: nil
        case .field(let name): name == "urgency" ? context.now.addingTimeInterval(1) : name == "status" ? FilterVirtualTag.waiting.nextEvaluation(context: context) : nil
        case .date(let expression): expression.nextEvaluation(context: context)
        case .predicate(let predicate): FilterExpression.predicate(predicate).nextEvaluation(context: context)
        case .unary(_, let child): child.nextEvaluation(context: context)
        case .binary(_, let left, let right): [left.nextEvaluation(context: context), right.nextEvaluation(context: context)].compactMap { $0 }.min()
        }
    }
}

enum TaskExpressionValue: Sendable {
    case boolean(Bool), integer(Int64), real(Double), text(String), date(TimeInterval), duration(Int64)

    var boolean: Bool {
        switch self {
        case .boolean(let value): return value
        case .integer(let value), .duration(let value): return value != 0
        case .real(let value), .date(let value): return value != 0
        case .text(let raw):
            let value = Self.dequoted(raw)
            return !value.isEmpty && value != "0" && value != "0.0"
        }
    }

    var trivial: Bool {
        if case .text(let value) = self { return value.isEmpty }
        return !boolean
    }

    func text(_ context: TaskFilterContext) -> String {
        switch self {
        case .boolean(let value): return value ? "true" : "false"
        case .integer(let value): return String(value)
        case .real(let value): return String(format: "%.6g", value)
        case .text(let value): return value
        case .duration(let value): return TaskAttributeValues.durationString(value)
        case .date(let value):
            let formatter = DateFormatter()
            formatter.calendar = context.calendar
            formatter.timeZone = context.calendar.timeZone
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            return formatter.string(from: Date(timeIntervalSince1970: value))
        }
    }

    var number: Double? {
        switch self {
        case .boolean(let value): value ? 1 : 0
        case .integer(let value), .duration(let value): Double(value)
        case .real(let value), .date(let value): value
        case .text: nil
        }
    }

    static func field(_ name: String, task: TaskRecord, context: TaskFilterContext) throws -> Self {
        if name == "urgency" { return .real(TaskDefaultUrgency.value(for: task, context: context)) }
        if name == "id" { throw TaskFilterError.unsupported("Numeric Taskwarrior IDs are device-local; use uuid instead.") }
        if name == "uuid" { return .text(task.id.uuidString.lowercased()) }
        if name == "status" { return .text(FilterVirtualTag.isWaiting(task, at: context.now) ? "waiting" : task.status) }
        if name == "tags" { return .text(task.tags.joined(separator: ",")) }
        if name.utf8.starts(with: "annotations.".utf8), name != "annotations.count" {
            let parts = name.split(separator: ".")
            guard (3...4).contains(parts.count), let index = Int(parts[1]), index > 0,
                  ["entry", "description"].contains(parts[2]), parts.count != 4 || parts[2] == "entry" else { throw TaskFilterError.unknownAttribute(name) }
            let notes = task.attributes.filter { $0.key.utf8.starts(with: "annotation_".utf8) }.sorted { UTF8String($0.key) < UTF8String($1.key) }
            guard index <= notes.count else { return .text(name) }
            let note = notes[index - 1]
            if parts[2] == "description" { return .text(note.value) }
            let date = FilterDateExpression.storedDate(String(decoding: note.key.utf8.dropFirst(11), as: UTF8.self)) ?? Date(timeIntervalSince1970: 0)
            if parts.count == 4 { return try .integer(dateComponent(String(parts[3]), date: date, context: context)) }
            return .date(date.timeIntervalSince1970)
        }
        if name == "annotations.count" { return .integer(Int64(task.attributes.filter { $0.key.utf8.starts(with: "annotation_".utf8) }.count)) }
        if name.utf8.starts(with: "tags.".utf8) {
            let tag = String(decoding: name.utf8.dropFirst(5), as: UTF8.self)
            return .text(task.attributes["tag_" + tag] == nil ? "" : tag)
        }
        if let dot = name.lastIndex(of: ".") {
            let base = String(name[..<dot]), component = String(name[name.index(after: dot)...])
            if context.schema.type(for: base) == .date {
                let date = FilterDateExpression.storedDate(task.attributes[base]) ?? Date(timeIntervalSince1970: 0)
                return try .integer(dateComponent(component, date: date, context: context))
            }
        }
        guard let raw = task.attributes[name] else { return .text("") }
        switch context.schema.type(for: name) ?? .string {
        case .string: return .text(raw)
        case .uuid:
            do { _ = try TaskAttributeValues.normalized(raw, for: TaskAttributeDefinition(name: name, type: .uuid)) }
            catch { throw TaskFilterError.invalidStoredValue(task.id, name, .uuid) }
            return .text(raw)
        case .numeric:
            guard raw.isEmpty || Float(raw)?.isFinite == true else { throw TaskFilterError.invalidStoredValue(task.id, name, .numeric) }
            return .real(Double(Float(raw) ?? 0))
        case .duration:
            guard raw.isEmpty || TaskwarriorDuration(raw, allowRawSeconds: false) != nil else { throw TaskFilterError.invalidStoredValue(task.id, name, .duration) }
            return .duration(TaskwarriorDuration(raw, allowRawSeconds: false)?.filterSeconds ?? 0)
        case .date:
            if context.schema.isUserDefined(name), !raw.isEmpty, Int64(raw) == nil { throw TaskFilterError.invalidStoredValue(task.id, name, .date) }
            guard let date = FilterDateExpression.storedDate(raw) else { return .text("") }
            return .date(date.timeIntervalSince1970)
        }
    }

    func applying(_ op: String, _ other: Self, context: TaskFilterContext, field: String? = nil) throws -> Self {
        if op == "and" || op == "&&" { return .boolean(boolean && other.boolean) }
        if op == "or" || op == "||" { return .boolean(boolean || other.boolean) }
        if op == "xor" { return .boolean(boolean != other.boolean) }
        if ["=", "==", "!=", "!==", "<", "<=", ">", ">=", "~", "!~"].contains(op) {
            return .boolean(try compare(op, other, context: context, field: field))
        }
        if op == "+", case .text = self { return .text(text(context) + Self.dequoted(other.text(context))) }
        if op == "+", case .text = other { return .text(text(context) + Self.dequoted(other.text(context))) }
        if op == "-", case .text(let left) = self, case .text(let right) = other { return .text(left + "-" + right) }
        if op == "*" {
            if case .text(let text) = self, case .integer(let count) = other {
                guard count > 0 else { throw TaskFilterError.evaluation("Taskwarrior string repetition needs a positive count.") }
                return try Self.repeated(text, count)
            }
            if case .integer(let count) = self, case .text(let text) = other { return try Self.repeated(Self.dequoted(text), count) }
            if case .boolean(let present) = self, case .text(let text) = other { return .text(present ? Self.dequoted(text) : "") }
            if case .text(let text) = self, case .boolean(let present) = other { return .text(present ? text : "") }
        }
        if case .boolean(let value) = self, case .integer = other, op == "+" || op == "*" {
            return try Self.integer(value ? 1 : 0).applying(op, other, context: context)
        }
        if case .integer = self, case .boolean(let value) = other, ["+", "-", "*"].contains(op) {
            return try applying(op, .integer(value ? 1 : 0), context: context)
        }
        guard let left = number, let right = other.number else { throw invalid(op) }
        if case .boolean = self {
            guard op == "+" || op == "*" else { throw invalid(op) }
            if case .boolean = other { throw invalid(op) }
        }
        if op == "/" || op == "%", case .boolean = other { throw invalid(op) }
        if op == "/" || op == "%", right == 0 { throw TaskFilterError.evaluation("Cannot \(op == "/" ? "divide" : "take a remainder") by zero.") }
        if op == "^" {
            guard case .integer = other else { throw TaskFilterError.evaluation("An exponent must be an integer.") }
            if case .date = self { throw invalid(op) }
            if case .duration = self { throw invalid(op) }
            let result = pow(left, right)
            if case .integer = self { return try .integer(Self.checkedInteger(result, bits: 32)) }
            return try Self.checkedReal(result)
        }
        let leftDate = if case .date = self { true } else { false }
        let rightDate = if case .date = other { true } else { false }
        let leftDuration = if case .duration = self { true } else { false }
        let rightDuration = if case .duration = other { true } else { false }
        if op == "-", case .real = self, rightDate || rightDuration { return try Self.checkedReal(left - right) }
        if leftDate || rightDate {
            guard op == "+" || op == "-", !(op == "+" && leftDate && rightDate), !(op == "-" && leftDuration && rightDate) else { throw invalid(op) }
            if op == "-", leftDate && rightDate { return try .duration(Self.checkedInteger(left - right)) }
            let lhs: Double
            if op == "+", case .real = self { lhs = Double(try Self.unsigned32(left)) }
            else { lhs = leftDate ? left : Double(try Self.checkedInteger(left)) }
            let rhs: Double
            if case .real = other { rhs = Double(try Self.checkedInteger(right, bits: 32)) }
            else { rhs = rightDate ? right : Double(try Self.checkedInteger(right)) }
            return .date(op == "+" ? lhs + rhs : lhs - rhs)
        }
        if leftDuration || rightDuration {
            guard op != "%", !(op == "*" && leftDuration && rightDuration) else { throw invalid(op) }
            if op == "/", leftDuration && rightDuration { return try Self.checkedReal(left / right) }
            let result: Double
            switch op {
            case "+":
                if case .real = self { result = Double(try Self.unsigned32(left)) + right }
                else { result = left + Double(try Self.checkedInteger(right, bits: { if case .real = other { 32 } else { 64 } }())) }
            case "-": result = left - Double(try Self.checkedInteger(right, bits: { if case .real = other { 32 } else { 64 } }()))
            case "*": result = left * right
            case "/": result = left / right
            default: throw invalid(op)
            }
            if op == "*", { if case .real = self { true } else if case .real = other { true } else { false } }() { return try .duration(Self.unsigned32(result)) }
            if op == "/", !leftDuration || { if case .real = other { true } else { false } }() { return try .duration(Self.unsigned32(result)) }
            return try .duration(Self.checkedInteger(result))
        }
        if case .integer(let lhs) = self, case .integer(let rhs) = other {
            switch op {
            case "+": let (v, overflow) = lhs.addingReportingOverflow(rhs); guard !overflow else { throw invalid(op) }; return .integer(v)
            case "-": let (v, overflow) = lhs.subtractingReportingOverflow(rhs); guard !overflow else { throw invalid(op) }; return .integer(v)
            case "*": let (v, overflow) = lhs.multipliedReportingOverflow(by: rhs); guard !overflow else { throw invalid(op) }; return .integer(v)
            case "/": guard !(lhs == .min && rhs == -1) else { throw invalid(op) }; return .integer(lhs / rhs)
            case "%": guard !(lhs == .min && rhs == -1) else { throw invalid(op) }; return .integer(lhs % rhs)
            default: throw invalid(op)
            }
        }
        switch op {
        case "+": return try Self.checkedReal(left + right)
        case "-": return try Self.checkedReal(left - right)
        case "*": return try Self.checkedReal(left * right)
        case "/": return try Self.checkedReal(left / right)
        case "%": return try Self.checkedReal(left.truncatingRemainder(dividingBy: right))
        default: throw invalid(op)
        }
    }

    private static func checkedInteger(_ value: Double, bits: Int = 64) throws -> Int64 {
        guard let result = Int64(exactly: value.rounded(.towardZero)), bits != 32 || Int32(exactly: result) != nil else { throw TaskFilterError.evaluation("Arithmetic exceeds Taskwarrior's defined integer range.") }
        return result
    }

    private static func unsigned32(_ value: Double) throws -> Int64 {
        Int64(UInt32(bitPattern: Int32(try checkedInteger(value, bits: 32))))
    }

    private static func checkedReal(_ value: Double) throws -> Self {
        guard value.isFinite else { throw TaskFilterError.evaluation("Arithmetic produced a non-finite value.") }
        return .real(value)
    }

    private static func repeated(_ text: String, _ count: Int64) throws -> Self {
        guard count >= 0, count <= 1_000_000, text.utf8.count <= 1_000_000 / max(1, Int(count)) else { throw TaskFilterError.evaluation("String repetition exceeds the safe expression limit.") }
        return .text(String(repeating: text, count: Int(count)))
    }

    private static func dateComponent(_ component: String, date: Date, context: TaskFilterContext) throws -> Int64 {
        let value: Int
        switch component {
        case "year": value = context.calendar.component(.year, from: date)
        case "month": value = context.calendar.component(.month, from: date)
        case "day": value = context.calendar.component(.day, from: date)
        case "hour": value = context.calendar.component(.hour, from: date)
        case "minute": value = context.calendar.component(.minute, from: date)
        case "second": value = context.calendar.component(.second, from: date)
        case "weekday": value = context.calendar.component(.weekday, from: date) - 1
        case "week":
            let yday = (context.calendar.ordinality(of: .day, in: .year, for: date) ?? 1) - 1
            let weekday = context.calendar.component(.weekday, from: date) - 1
            value = (yday + 7 - weekday) / 7
        case "julian": value = context.calendar.ordinality(of: .day, in: .year, for: date) ?? 0
        default: throw TaskFilterError.unknownAttribute(component)
        }
        return Int64(value)
    }

    static func dequoted(_ raw: String) -> String {
        let bytes = Array(raw.utf8)
        guard let first = bytes.first, bytes.count >= 2, first == bytes.last, first == 34 || first == 39 else { return raw }
        return String(decoding: bytes.dropFirst().dropLast(), as: UTF8.self)
    }

    private func invalid(_ op: String) -> TaskFilterError { .evaluation("Operator ‘\(op)’ cannot be applied to these values or exceeds its defined range.") }

    private var comparisonTrivial: Bool {
        switch self {
        case .text(let value): Self.dequoted(value).isEmpty
        case .boolean: false
        default: trivial
        }
    }

    private func compare(_ op: String, _ other: Self, context: TaskFilterContext, field: String?) throws -> Bool {
        if op == "~" || op == "!~" { return try FilterRegex(Self.dequoted(other.text(context))).matches(Self.dequoted(text(context))) != (op == "!~") }
        if case .boolean(let left) = self, case .boolean(let right) = other {
            switch op {
            case "<", ">": return !left && right
            case "<=": return !left || right
            case ">=": return left || !right
            case "=", "==": return left == right
            case "!=", "!==": return left != right
            default: break
            }
        }
        var lhs = Self.dequoted(text(context)), rhs = Self.dequoted(other.text(context))
        if field == "status" { lhs = lhs.lowercased(); rhs = rhs.lowercased() }
        let equal: Bool, partial: Bool, less: Bool, greater: Bool
        if let field, let values = context.schema.orderedValues(for: field), case .text = self, case .text = other {
            let order = values.reversed().map { UTF8String($0) }
            let left = order.firstIndex(of: UTF8String(lhs)) ?? order.endIndex
            let right = order.firstIndex(of: UTF8String(rhs)) ?? order.endIndex
            equal = lhs.matchesBytes(rhs); partial = lhs.isEmpty == rhs.isEmpty && lhs.utf8.starts(with: rhs.utf8)
            less = !equal && left < right; greater = !equal && left > right
        } else if case .date(let left) = self {
            let right = try other.dateValue(context)
            equal = left == right
            partial = context.calendar.isDate(Date(timeIntervalSince1970: left), inSameDayAs: Date(timeIntervalSince1970: right))
            less = !comparisonTrivial && !other.comparisonTrivial && left < right; greater = !comparisonTrivial && !other.comparisonTrivial && left > right
        } else if case .date(let right) = other {
            let left = try dateValue(context)
            equal = left == right; partial = equal
            less = !comparisonTrivial && !other.comparisonTrivial && left < right; greater = !comparisonTrivial && !other.comparisonTrivial && left > right
        } else if case .duration = self {
            let left = try durationValue(context), right = try other.durationValue(context)
            equal = left == right; partial = equal
            less = !comparisonTrivial && !other.comparisonTrivial && left < right; greater = !comparisonTrivial && !other.comparisonTrivial && left > right
        } else if case .duration = other {
            let left = try durationValue(context), right = try other.durationValue(context)
            equal = left == right; partial = equal
            less = !comparisonTrivial && !other.comparisonTrivial && left < right; greater = !comparisonTrivial && !other.comparisonTrivial && left > right
        } else if let left = number, let right = other.number {
            equal = left == right; partial = equal; less = left < right; greater = left > right
        } else {
            equal = lhs.matchesBytes(rhs)
            partial = if case .text = self { lhs.isEmpty == rhs.isEmpty && lhs.utf8.starts(with: rhs.utf8) } else { equal }
            let bothStrings: Bool = if case .text = self, case .text = other { true } else { false }
            less = (!bothStrings || (!comparisonTrivial && !other.comparisonTrivial)) && UTF8String(lhs) < UTF8String(rhs)
            greater = (!bothStrings || (!comparisonTrivial && !other.comparisonTrivial)) && UTF8String(rhs) < UTF8String(lhs)
        }
        switch op {
        case "=": return field == "status" ? equal : partial
        case "!=": return field == "status" ? !equal : !partial
        case "==": return equal
        case "!==": return !equal
        case "<": return less
        case ">": return greater
        case "<=", ">=":
            let temporal = { if case .duration = self { return true }; if case .duration = other { return true }; if case .date = self { return true }; if case .date = other { return true }; return false }()
            if temporal && (comparisonTrivial || other.comparisonTrivial) { return false }
            return equal || (op == "<=" ? less : greater)
        default: return false
        }
    }

    private func dateValue(_ context: TaskFilterContext) throws -> Double {
        switch self {
        case .date(let value): return value
        case .duration(let value): return context.now.timeIntervalSince1970 + Double(value)
        case .integer(let value): return Double(value)
        case .real(let value): return Double(try Self.checkedInteger(value, bits: 32))
        case .boolean(let value): return value ? 1 : 0
        case .text(let value): return try FilterDateExpression(Self.dequoted(value)).resolve(context)?.timeIntervalSince1970 ?? 0
        }
    }

    private func durationValue(_ context: TaskFilterContext) throws -> Int64 {
        switch self {
        case .duration(let value), .integer(let value): return value
        case .real(let value): return try Self.checkedInteger(value, bits: 32)
        case .date(let value): return try Self.checkedInteger(value - context.now.timeIntervalSince1970)
        case .boolean(let value): return value ? 1 : 0
        case .text(let value): return TaskwarriorDuration(Self.dequoted(value), allowRawSeconds: false)?.filterSeconds ?? 0
        }
    }
}

extension TaskValueExpression {
    func validate(schema: TaskFilterSchema) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let context = TaskFilterContext(tasks: [], now: Date(timeIntervalSince1970: 0), calendar: calendar, schema: schema)
        _ = try validationValue(context)
    }

    private func validationValue(_ context: TaskFilterContext) throws -> (value: TaskExpressionValue, constant: Bool) {
        switch self {
        case .literal(let value): return (value, true)
        case .predicate, .identity: return (.boolean(true), false)
        case .date: return (.date(1), false)
        case .field(let name):
            if name.hasPrefix("annotations."), name.hasSuffix(".description") { return (.text("expression"), false) }
            if name.hasPrefix("annotations."), name.hasSuffix(".entry") { return (.date(1), false) }
            if name == "annotations.count" || name.contains(".") && !name.hasPrefix("tags.") { return (.integer(1), false) }
            switch context.schema.type(for: name) ?? .string {
            case .numeric: return (.real(1), false)
            case .duration: return (.duration(1), false)
            case .date: return (.date(1), false)
            default: return (.text("expression"), false)
            }
        case .unary(let op, let child):
            let result = try child.validationValue(context)
            if op == "!" { return (.boolean(!result.value.boolean), result.constant) }
            if op == "+" { return result }
            return (try TaskExpressionValue.integer(0).applying("-", result.value, context: context), result.constant)
        case .binary(let op, let left, let right):
            let lhs = try left.validationValue(context), rhs = try right.validationValue(context)
            if ["=", "==", "!=", "!==", "<", "<=", ">", ">="].contains(op) { return (.boolean(true), false) }
            if op == "~" || op == "!~" {
                if rhs.constant { _ = try FilterRegex(TaskExpressionValue.dequoted(rhs.value.text(context))) }
                return (.boolean(true), false)
            }
            let value = try lhs.value.applying(op, rhs.value, context: context)
            if lhs.constant && rhs.constant { return (value, true) }
            switch value {
            case .integer: return (.integer(1), false)
            case .real: return (.real(1), false)
            case .duration: return (.duration(1), false)
            case .date: return (.date(1), false)
            default: return (value, false)
            }
        }
    }
}
