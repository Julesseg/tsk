import CTaskFilterRegex
import Foundation

final class FilterRegex: @unchecked Sendable {
    private let handle: OpaquePointer
    let pattern: String

    init(_ pattern: String) throws {
        self.pattern = pattern
        var error: UnsafeMutablePointer<CChar>?
        let bytes = Array(pattern.utf8)
        let handle = bytes.withUnsafeBytes { buffer in
            tsk_filter_regex_create(buffer.baseAddress?.assumingMemoryBound(to: CChar.self), buffer.count, &error)
        }
        defer { if let error { tsk_filter_regex_error_free(error) } }
        guard let handle else {
            throw TaskFilterError.invalidRegex(pattern, error.map { String(cString: $0) } ?? "Could not compile the pattern.")
        }
        self.handle = handle
    }

    deinit { tsk_filter_regex_destroy(handle) }

    func matches(_ text: String) throws -> Bool {
        let bytes = Array(text.utf8)
        let result = bytes.withUnsafeBytes { buffer in
            tsk_filter_regex_search(handle, buffer.baseAddress?.assumingMemoryBound(to: CChar.self), buffer.count)
        }
        guard result >= 0 else { throw TaskFilterError.invalidRegex(pattern, "The regex engine could not evaluate this pattern.") }
        return result == 1
    }
}

enum FilterComparison: Sendable {
    case partial, notPartial, exact, notExact, less, greater, by
    case regex(FilterRegex, inverted: Bool)
}

enum FilterPredicate: Sendable {
    case tag(String, present: Bool)
    case virtualTag(FilterVirtualTag, present: Bool)
    case date(FilterDatePredicate)
    case typed(FilterTypedPredicate)
    case comparison(name: String, operation: FilterComparison, value: String)

    static func search(_ pattern: String) throws -> Self {
        .comparison(name: "description", operation: .regex(try FilterRegex(pattern), inverted: false), value: pattern)
    }

    static func attribute(_ name: String, modifier: String, value: String) throws -> Self {
        let operation: FilterComparison
        var operand = value
        switch modifier {
        case "": operation = .partial
        case "not": operation = .notPartial
        case "is", "equals": operation = .exact
        case "isnt": operation = .notExact
        case "none": operation = .exact; operand = ""
        case "any": operation = .notExact; operand = ""
        case "before", "under", "below": operation = .less
        case "after", "over", "above": operation = .greater
        case "by": operation = .by
        case "has", "contains": operation = .regex(try FilterRegex(value), inverted: false)
        case "hasnt": operation = .regex(try FilterRegex(value), inverted: true)
        case "startswith", "left": operation = .regex(try FilterRegex("^" + value), inverted: false)
        case "endswith", "right": operation = .regex(try FilterRegex(value + "$"), inverted: false)
        case "word", "noword": throw TaskFilterError.unsupported(".\(modifier) differs between Taskwarrior hosts; use an explicit ECMAScript pattern instead.")
        default: throw TaskFilterError.syntax("Unrecognized attribute modifier ‘\(modifier)’.", byteOffset: 0)
        }
        return .comparison(name: name, operation: operation, value: operand)
    }

    private static func statusEquals(_ lhs: String, _ rhs: String) -> Bool {
        func folded(_ text: String) -> [UInt8] {
            text.utf8.map { (65...90).contains($0) ? $0 + 32 : $0 }
        }
        return folded(lhs) == folded(rhs)
    }

    func includes(_ task: TaskRecord, context: TaskFilterContext) throws -> Bool {
        switch self {
        case .typed(let predicate): return try predicate.includes(task, context: context)
        case .date(let predicate): return try predicate.includes(task, context: context)
        case .virtualTag(let tag, let present): return try tag.includes(task, context: context) == present
        case .tag(let tag, let present): return (task.attributes["tag_\(tag)"] != nil) == present
        case .comparison(let name, let operation, let value):
            let actual: String
            if name == "uuid" { actual = task.id.uuidString.lowercased() }
            else if name == "status", FilterVirtualTag.isWaiting(task, at: context.now) { actual = "waiting" }
            else if name == "tags" { actual = task.tags.joined(separator: ",") }
            else { actual = task.attributes[name] ?? "" }
            if context.schema.type(for: name) == .uuid, !actual.isEmpty {
                do { _ = try TaskAttributeValues.normalized(actual, for: TaskAttributeDefinition(name: name, type: .uuid)) }
                catch { throw TaskFilterError.invalidStoredValue(task.id, name, .uuid) }
            }
            if let values = context.schema.orderedValues(for: name) {
                let ordered = values.reversed().map { UTF8String($0) }
                let left = ordered.firstIndex(of: UTF8String(actual)) ?? ordered.endIndex
                let right = ordered.firstIndex(of: UTF8String(value)) ?? ordered.endIndex
                switch operation {
                case .less: return !actual.matchesBytes(value) && left < right
                case .greater: return !actual.matchesBytes(value) && left > right
                case .by: return actual.matchesBytes(value) || left <= right
                default: break
                }
            }
            switch operation {
            case .partial, .notPartial:
                let matches: Bool
                if name == "status" { matches = Self.statusEquals(actual, value) }
                else { matches = actual.isEmpty == value.isEmpty && actual.utf8.starts(with: value.utf8) }
                if case .notPartial = operation { return !matches }
                return matches
            case .exact, .notExact:
                let matches = name == "status" ? Self.statusEquals(actual, value) : actual.matchesBytes(value)
                if case .notExact = operation { return !matches }
                return matches
            case .less: return !actual.isEmpty && !value.isEmpty && UTF8String(actual) < UTF8String(value)
            case .greater: return !actual.isEmpty && !value.isEmpty && UTF8String(value) < UTF8String(actual)
            case .by: return actual.matchesBytes(value) || (!actual.isEmpty && !value.isEmpty && !(UTF8String(value) < UTF8String(actual)))
            case .regex(let regex, let inverted):
                var matches = try regex.matches(actual)
                if !matches, name == "description" {
                    for (key, note) in task.attributes where key.utf8.starts(with: "annotation_".utf8) {
                        if try regex.matches(note) { matches = true; break }
                    }
                }
                return matches != inverted
            }
        }
    }
}
