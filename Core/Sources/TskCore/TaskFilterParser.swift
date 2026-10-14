import Foundation

struct FilterToken: Sendable {
    enum Kind: Sendable {
        case atom(String, quoted: Bool), pattern(String), left, right, negation, and, or, xor
    }
    let kind: Kind
    let offset: Int
}

struct FilterLexer {
    let bytes: [UInt8]
    var index = 0

    init(_ expression: String) { bytes = Array(expression.utf8) }

    mutating func tokens() throws -> [FilterToken] {
        var result: [FilterToken] = []
        while index < bytes.count {
            if [9, 10, 13, 32].contains(bytes[index]) { index += 1; continue }
            let offset = index
            let kind: FilterToken.Kind
            switch bytes[index] {
            case 40: index += 1; kind = .left
            case 41: index += 1; kind = .right
            case 33: index += 1; kind = .negation
            case 47:
                index += 1
                var pattern: [UInt8] = []
                var closed = false
                while index < bytes.count {
                    let byte = bytes[index]
                    if byte == 47 { index += 1; closed = true; break }
                    if byte == 92, index + 1 < bytes.count {
                        pattern.append(byte); index += 1
                        pattern.append(bytes[index]); index += 1
                    } else { pattern.append(byte); index += 1 }
                }
                guard closed else { throw TaskFilterError.syntax("Unclosed /pattern/.", byteOffset: offset) }
                if index < bytes.count, ![9, 10, 13, 32, 40, 41].contains(bytes[index]) {
                    throw TaskFilterError.unsupported("Regex flags are not supported; use the case-sensitive Taskwarrior defaults.")
                }
                kind = .pattern(String(decoding: pattern, as: UTF8.self))
            default:
                var value: [UInt8] = []
                var quoted = false
                while index < bytes.count, ![9, 10, 13, 32, 40, 41].contains(bytes[index]) {
                    let byte = bytes[index]
                    if byte == 34 || byte == 39 {
                        quoted = true
                        index += 1
                        var closed = false
                        while index < bytes.count {
                            if bytes[index] == byte { index += 1; closed = true; break }
                            if bytes[index] == 92, index + 1 < bytes.count, bytes[index + 1] == byte {
                                index += 1
                            }
                            value.append(bytes[index]); index += 1
                        }
                        guard closed else { throw TaskFilterError.syntax("Unclosed quoted value.", byteOffset: offset) }
                    } else if byte == 92, index + 1 < bytes.count, [9, 10, 13, 32, 40, 41].contains(bytes[index + 1]) {
                        index += 1; value.append(bytes[index]); index += 1
                    } else { value.append(byte); index += 1 }
                }
                let atom = String(decoding: value, as: UTF8.self)
                if !quoted, atom == "and" { kind = .and }
                else if !quoted, atom == "or" { kind = .or }
                else if !quoted, atom == "xor" { kind = .xor }
                else { kind = .atom(atom, quoted: quoted) }
            }
            result.append(FilterToken(kind: kind, offset: offset))
        }
        return result
    }
}

struct FilterParser {
    let tokens: [FilterToken]
    let schema: TaskFilterSchema
    var index = 0

    init(_ expression: String, schema: TaskFilterSchema) throws {
        var lexer = FilterLexer(expression)
        tokens = try lexer.tokens()
        self.schema = schema
    }

    mutating func parse() throws -> FilterExpression {
        if tokens.isEmpty { return .all }
        let expression = try xor()
        guard index == tokens.count else { throw syntax("Unexpected token.") }
        return expression
    }

    private mutating func xor() throws -> FilterExpression {
        var expression = try or()
        while index < tokens.count, case .xor = tokens[index].kind {
            index += 1; expression = .xor(expression, try or())
        }
        return expression
    }

    private mutating func or() throws -> FilterExpression {
        var expression = try and()
        while index < tokens.count, case .or = tokens[index].kind {
            index += 1; expression = .or(expression, try and())
        }
        return expression
    }

    private mutating func and() throws -> FilterExpression {
        var expression = try primary()
        while index < tokens.count {
            switch tokens[index].kind {
            case .and: index += 1; expression = .and(expression, try primary())
            case .atom, .pattern, .left, .negation: expression = .and(expression, try primary())
            default: return expression
            }
        }
        return expression
    }

    private mutating func primary() throws -> FilterExpression {
        guard index < tokens.count else { throw syntax("Expected a predicate.") }
        let token = tokens[index]
        index += 1
        switch token.kind {
        case .left:
            let expression = try xor()
            guard index < tokens.count, case .right = tokens[index].kind else { throw syntax("Expected closing parenthesis.") }
            index += 1
            return expression
        case .negation: return .not(try primary())
        case .pattern(let pattern): return .predicate(try .search(pattern))
        case .atom(let atom, let quoted): return .predicate(try predicate(atom, quoted: quoted, offset: token.offset))
        default: throw TaskFilterError.syntax("Expected a predicate.", byteOffset: token.offset)
        }
    }

    private func predicate(_ atom: String, quoted: Bool, offset: Int) throws -> FilterPredicate {
        let bytes = Array(atom.utf8)
        if !quoted, let first = bytes.first, first == 43 || first == 45 {
            let tag = String(decoding: bytes.dropFirst(), as: UTF8.self)
            guard !tag.isEmpty else { throw TaskFilterError.syntax("Expected a tag name.", byteOffset: offset) }
            if let virtual = FilterVirtualTag(rawValue: tag) { return .virtualTag(virtual, present: first == 43) }
            if tag == "LATEST" { throw TaskFilterError.unsupported("+LATEST requires device-local Taskwarrior working-set IDs.") }
            if tag.unicodeScalars.allSatisfy({ (65...90).contains($0.value) }) {
                throw TaskFilterError.unsupported("Virtual tag ‘\(tag)’ requires the virtual-tag filter support.")
            }
            return .tag(tag, present: first == 43)
        }
        if let colon = bytes.firstIndex(of: 58) {
            let attribute = String(decoding: bytes[..<colon], as: UTF8.self)
            let value = String(decoding: bytes[(colon + 1)...], as: UTF8.self)
            let parts = attribute.split(separator: ".", omittingEmptySubsequences: false)
            let name = parts.count > 1 ? parts.dropLast().joined(separator: ".") : attribute
            let modifier = parts.count > 1 ? String(parts.last!) : ""
            guard let type = schema.attributes[UTF8String(name)] else { throw TaskFilterError.unknownAttribute(name) }
            if type == .date { return .date(try FilterDatePredicate(name: name, modifier: modifier, value: value)) }
            guard type == .string else { throw TaskFilterError.unsupported("\(name) uses \(type.rawValue) semantics; this schema type requires its typed filter support.") }
            return try .attribute(name, modifier: modifier, value: value)
        }
        if !quoted, atom.unicodeScalars.allSatisfy({ (48...57).contains($0.value) }) {
            throw TaskFilterError.unsupported("Numeric Taskwarrior IDs are device-local; filter by uuid instead.")
        }
        if !quoted, UUID(uuidString: atom) != nil { return try .attribute("uuid", modifier: "is", value: atom.lowercased()) }
        if ["=", "==", "!=", "!==", "<", ">", "<=", ">=", "~", "!~", "*", "^", "%"].contains(atom) {
            throw TaskFilterError.unsupported("Direct comparison or arithmetic operator ‘\(atom)’ requires expression operand support.")
        }
        return try .search(atom)
    }

    private func syntax(_ message: String) -> TaskFilterError {
        .syntax(message, byteOffset: index < tokens.count ? tokens[index].offset : (tokens.last?.offset ?? 0))
    }
}
