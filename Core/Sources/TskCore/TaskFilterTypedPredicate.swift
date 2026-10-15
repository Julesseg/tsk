import Foundation

struct FilterTypedPredicate: Sendable {
    let name: String
    let type: TaskFilterAttributeType
    let operation: FilterComparison
    let operand: FilterScalar

    init(name: String, type: TaskFilterAttributeType, modifier: String, value: String, quoted: Bool = false) throws {
        let modifier = ["startswith", "left", "endswith", "right"].contains(modifier) ? "has" : modifier
        guard case .comparison(_, let operation, let raw) = try FilterPredicate.attribute(name, modifier: modifier, value: value) else {
            throw TaskFilterError.unsupported("The modifier cannot be applied to this typed attribute.")
        }
        self.name = name
        self.type = type
        let operand: FilterScalar
        if quoted || raw.isEmpty || FilterScalar.isUUIDLiteral(raw) { operand = .text(raw) }
        else if let number = FilterScalar.numericOperand(raw) { operand = .number(number) }
        else if type == .duration, let duration = TaskwarriorDuration(raw, allowRawSeconds: false) { operand = .duration(duration.seconds) }
        else if case .regex = operation {
            guard !raw.utf8.contains(where: { [43, 45, 42, 47, 94, 37].contains($0) }) else {
                throw TaskFilterError.unsupported("Quote typed regex patterns containing expression operators.")
            }
            operand = .text(raw)
        }
        else if type == .uuid { operand = .text(raw) }
        else { throw TaskFilterError.syntax("‘\(name)’ requires a valid \(type.rawValue) operand.", byteOffset: 0) }
        self.operand = operand
        if case .regex(_, let inverted) = operation {
            self.operation = .regex(try FilterRegex(operand.text), inverted: inverted)
        } else { self.operation = operation }
    }

    func includes(_ task: TaskRecord, context: TaskFilterContext) throws -> Bool {
        let actual: FilterScalar
        if let stored = task.attributes[name] {
            switch type {
            case .numeric:
                guard stored.isEmpty || Float(stored)?.isFinite == true else { throw TaskFilterError.invalidStoredValue(task.id, name, type) }
                actual = .number(Double(Float(stored) ?? 0))
            case .uuid:
                do { _ = try TaskAttributeValues.normalized(stored, for: TaskAttributeDefinition(name: name, type: .uuid)) }
                catch { throw TaskFilterError.invalidStoredValue(task.id, name, type) }
                actual = .text(stored)
            case .duration:
                guard stored.isEmpty || TaskwarriorDuration(stored, allowRawSeconds: false) != nil else { throw TaskFilterError.invalidStoredValue(task.id, name, type) }
                actual = .duration(TaskwarriorDuration(stored, allowRawSeconds: false)?.seconds ?? 0)
            default: throw TaskFilterError.unsupported("This attribute type has no scalar predicate.")
            }
        } else { actual = .text("") }
        return try actual.matches(operation, operand: operand)
    }
}

enum FilterScalar: Sendable {
    case text(String), number(Double), duration(Int64)

    static func isUUIDLiteral(_ raw: String) -> Bool {
        let bytes = Array(raw.utf8)
        let pattern = Array("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx".utf8)
        guard (8...36).contains(bytes.count) else { return false }
        return bytes.enumerated().allSatisfy { index, byte in
            pattern[index] == 45 ? byte == 45 : (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
        }
    }

    static func numericOperand(_ raw: String) -> Double? {
        let pattern = #"^[+-]?(?:0|[1-9][0-9]*)(?:\.[0-9]*)?(?:[eE][+-]?(?:[0-9]+(?:\.[0-9]*)?)?)?$"#
        guard raw.range(of: pattern, options: .regularExpression) != nil,
              let range = raw.range(of: #"^[+-]?(?:0|[1-9][0-9]*)(?:\.[0-9]*)?(?:[eE][+-]?[0-9]+)?"#, options: .regularExpression),
              let number = Double(raw[range]), number.isFinite else { return nil }
        return number
    }

    var text: String {
        switch self {
        case .text(let value): value
        case .number(let value): String(format: "%.6g", value)
        case .duration(let value): TaskAttributeValues.durationString(value)
        }
    }

    private var trivial: Bool {
        switch self {
        case .text(let value): value.isEmpty
        case .number(let value): value == 0
        case .duration(let value): value == 0
        }
    }

    private var duration: Int64? {
        switch self {
        case .duration(let value): value
        case .number(let value): Int64(exactly: value.rounded(.towardZero))
        case .text(let value): TaskwarriorDuration(value, allowRawSeconds: false)?.seconds ?? 0
        }
    }

    func matches(_ operation: FilterComparison, operand: Self) throws -> Bool {
        if case .regex(let regex, let inverted) = operation { return try regex.matches(text) != inverted }
        let equal: Bool
        let less: Bool
        let greater: Bool
        let partial: Bool
        switch (self, operand) {
        case (.number(let left), .number(let right)):
            equal = left == right; partial = equal; less = left < right; greater = left > right
        case (.duration, _), (_, .duration):
            guard let left = duration, let right = operand.duration else { throw TaskFilterError.unsupported("Duration conversion exceeds the supported range.") }
            equal = left == right; partial = equal
            less = !trivial && !operand.trivial && left < right
            greater = !trivial && !operand.trivial && left > right
        default:
            equal = text.matchesBytes(operand.text)
            if case .text = self, case .text = operand {
                partial = text.isEmpty == operand.text.isEmpty && text.utf8.starts(with: operand.text.utf8)
                less = !trivial && !operand.trivial && UTF8String(text) < UTF8String(operand.text)
                greater = !trivial && !operand.trivial && UTF8String(operand.text) < UTF8String(text)
            } else {
                if case .text = self { partial = text.isEmpty == operand.text.isEmpty && text.utf8.starts(with: operand.text.utf8) }
                else { partial = equal }
                less = UTF8String(text) < UTF8String(operand.text)
                greater = UTF8String(operand.text) < UTF8String(text)
            }
        }
        switch operation {
        case .partial: return partial
        case .notPartial: return !partial
        case .exact: return equal
        case .notExact: return !equal
        case .less: return less
        case .greater: return greater
        case .by:
            if case .duration = self, trivial || operand.trivial { return false }
            if case .duration = operand, trivial || operand.trivial { return false }
            return equal || less
        case .regex: return false
        }
    }
}
