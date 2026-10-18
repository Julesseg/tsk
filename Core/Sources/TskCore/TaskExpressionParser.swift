import Foundation

struct TaskExpressionParser {
    struct Token {
        enum Kind { case atom(String, Bool), identity([String]), op(String), left, right }
        let kind: Kind
        let offset: Int
    }

    let tokens: [Token]
    let schema: TaskFilterSchema
    var allowsInitialNumber = false
    var index = 0

    init(_ raw: String, schema: TaskFilterSchema, rewriteIdentity: Bool = true) throws {
        self.schema = schema
        let rawTokens = try Self.lex(raw, schema: schema)
        if rewriteIdentity {
            let uuids = rawTokens.compactMap { token -> String? in
                if case .atom(let atom, false) = token.kind, FilterScalar.isUUIDLiteral(atom) { return atom }
                return nil
            }
            var rewritten: [Token] = [], inserted = false
            for token in rawTokens {
                if case .atom(let atom, false) = token.kind, FilterScalar.isUUIDLiteral(atom) {
                    if !inserted {
                        inserted = true
                        rewritten.append(Token(kind: .identity(uuids), offset: token.offset))
                    }
                } else { rewritten.append(token) }
            }
            tokens = rewritten
        } else { tokens = rawTokens }
    }

    var hasValueOperators: Bool {
        tokens.contains {
            switch $0.kind {
            case .identity: true
            case .op(let op): !["and", "or", "xor", "!"].contains(op)
            case .atom(let atom, let quoted): !quoted && (dynamicAttribute(atom) != nil || schema.contains(atom))
            default: false
            }
        }
    }

    mutating func parse() throws -> TaskValueExpression {
        let result = try expression(0, operand: false)
        guard index == tokens.count else { throw syntax("Unexpected expression operand.") }
        return result
    }

    private static func precedence(_ op: String) -> Int {
        switch op {
        case "xor": 3
        case "or", "||": 4
        case "and", "&&": 5
        case "~", "!~": 8
        case "=", "==", "!=", "!==": 9
        case "<", "<=", ">", ">=": 10
        case "+", "-": 12
        case "*", "/", "%": 13
        case "^": 16
        default: -1
        }
    }

    private mutating func expression(_ minimum: Int, operand: Bool) throws -> TaskValueExpression {
        var left = try primary(operand: operand)
        while index < tokens.count {
            if case .right = tokens[index].kind { break }
            let op: String
            let implicit: Bool
            if case .op(let value) = tokens[index].kind, value != "!" {
                op = value; implicit = false
            } else { op = "and"; implicit = true }
            let precedence = Self.precedence(op)
            if precedence < minimum { break }
            if !implicit { index += 1 }
            let right = try expression(op == "^" ? precedence : precedence + 1, operand: precedence > 5)
            left = .binary(op, left, right)
        }
        return left
    }

    private mutating func primary(operand: Bool) throws -> TaskValueExpression {
        guard index < tokens.count else { throw syntax("Expected an expression operand.") }
        let token = tokens[index]
        index += 1
        switch token.kind {
        case .left:
            let value = try expression(0, operand: operand)
            guard index < tokens.count, case .right = tokens[index].kind else { throw syntax("Expected closing parenthesis.") }
            index += 1
            return value
        case .right: throw syntax("Unexpected closing parenthesis.")
        case .identity(let prefixes): return .identity(prefixes)
        case .op(let op):
            guard ["!", "+", "-"].contains(op) else { throw syntax("Expected an operand before ‘\(op)’.") }
            return .unary(op, try expression(15, operand: op != "!"))
        case .atom(let atom, let quoted):
            let hasFollowingOperator: Bool
            if index < tokens.count, case .op(let op) = tokens[index].kind { hasFollowingOperator = Self.precedence(op) > 5 }
            else { hasFollowingOperator = false }
            if let dynamic = dynamicAttribute(atom), !quoted {
                var parser = try TaskExpressionParser(dynamic.value, schema: schema, rewriteIdentity: false)
                parser.allowsInitialNumber = true
                return .binary(dynamic.op, .field(dynamic.name), try parser.expression(0, operand: true))
            }
            if !quoted, schema.contains(atom) {
                if atom == "id" { throw TaskFilterError.unsupported("Numeric Taskwarrior IDs are device-local; use uuid instead.") }
                return .field(atom)
            }
            if !operand && !hasFollowingOperator {
                let parser = try FilterParser("", schema: schema)
                if !quoted, atom.hasPrefix("/"), atom.hasSuffix("/") { return .predicate(try .search(String(atom.dropFirst().dropLast()))) }
                var lexer = FilterLexer(atom)
                if let first = try lexer.tokens().first, case .atom(let value, let quoted) = first.kind { return .predicate(try parser.predicate(value, quoted: quoted, offset: token.offset)) }
                throw syntax("Expected a predicate.")
            }
            if quoted { return .literal(.text(atom)) }
            if atom.utf8.starts(with: "annotations.".utf8) {
                let parts = atom.split(separator: ".")
                let valid = atom == "annotations.count" || ((3...4).contains(parts.count) && Int(parts[1]) != nil && ["description", "entry"].contains(parts[2]) && (parts.count == 3 || parts[2] == "entry" && ["year", "month", "day", "week", "weekday", "julian", "hour", "minute", "second"].contains(parts[3])))
                guard valid else { throw TaskFilterError.unknownAttribute(atom) }
                return .field(atom)
            }
            if atom.utf8.starts(with: "tags.".utf8) { return .field(atom) }
            if let dot = atom.lastIndex(of: "."), schema.type(for: String(atom[..<dot])) == .date {
                let suffix = String(atom[atom.index(after: dot)...])
                guard ["year", "month", "day", "week", "weekday", "julian", "hour", "minute", "second"].contains(suffix) else { throw TaskFilterError.unknownAttribute(atom) }
                return .field(atom)
            }
            if atom == "true" { return .literal(.boolean(true)) }
            if atom == "false" { return .literal(.boolean(false)) }
            if atom == "pi" { return .literal(.real(3.14159165)) }
            if FilterScalar.isUUIDLiteral(atom) || atom.range(of: #"^[0-9]+(?:-[0-9]+|(?:,[0-9]+)+)$"#, options: .regularExpression) != nil { return .literal(.text(atom)) }
            if atom.utf8.allSatisfy({ (48...57).contains($0) }), let date = try? FilterDateExpression(atom), date.numericVariant == nil { return .date(date) }
            if let number = FilterScalar.numericOperand(atom) {
                if !allowsInitialNumber, index == 1 || (index >= 2 && { if case .left = tokens[index - 2].kind { true } else { false } }()) {
                    throw TaskFilterError.unsupported("Taskwarrior rewrites this number as a device-local ID. Start the parenthesized operand with a field or unary sign; use uuid for task identity.")
                }
                if atom.utf8.allSatisfy({ (48...57).contains($0) }), let integer = Int64(atom) { return .literal(.integer(integer)) }
                return .literal(.real(number))
            }
            if let duration = TaskwarriorDuration(atom, allowRawSeconds: false) { return .literal(.duration(duration.filterSeconds)) }
            if let date = try? FilterDateExpression(atom) { return .date(date) }
            if hasFollowingOperator && !operand { throw TaskFilterError.unknownAttribute(atom) }
            return .literal(.text(atom))
        }
    }

    private func dynamicAttribute(_ atom: String) -> (name: String, op: String, value: String)? {
        guard let colon = atom.firstIndex(of: ":") else { return nil }
        let prefix = String(atom[..<colon]), value = String(atom[atom.index(after: colon)...])
        let pieces = prefix.split(separator: ".", omittingEmptySubsequences: false)
        let name = pieces.count > 1 ? pieces.dropLast().joined(separator: ".") : prefix
        guard let type = schema.type(for: name), type == .numeric || type == .duration else { return nil }
        let epochDate: Bool = if !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }), !FilterScalar.isUUIDLiteral(value), let date = try? FilterDateExpression(value) { date.numericVariant == nil } else { false }
        let arithmetic = FilterScalar.numericOperand(value) == nil && TaskwarriorDuration(value, allowRawSeconds: false) == nil && value.utf8.contains { [43, 45, 42, 47, 94, 37].contains($0) }
        guard epochDate || arithmetic else { return nil }
        let modifier = pieces.count > 1 ? String(pieces.last!) : ""
        let op: String
        switch modifier {
        case "": op = "="
        case "is", "equals": op = "=="
        case "isnt": op = "!=="
        case "not": op = "!="
        case "below", "before", "under": op = "<"
        case "above", "after", "over": op = ">"
        case "by": op = "<="
        default: return nil
        }
        return (name, op, value)
    }

    private func syntax(_ message: String) -> TaskFilterError { .syntax(message, byteOffset: index < tokens.count ? tokens[index].offset : tokens.last?.offset ?? 0) }

    private static func lex(_ raw: String, schema: TaskFilterSchema) throws -> [Token] {
        let bytes = Array(raw.utf8)
        var result: [Token] = [], index = 0
        var expectingValue = true
        let operators = ["!==", "==", "!=", "<=", ">=", "!~", "&&", "||", "+", "-", "*", "/", "%", "^", "<", ">", "=", "~", "!"]
        while index < bytes.count {
            if [9, 10, 13, 32].contains(bytes[index]) { index += 1; continue }
            let start = index
            if bytes[index] == 40 { result.append(Token(kind: .left, offset: start)); index += 1; expectingValue = true; continue }
            if bytes[index] == 41 { result.append(Token(kind: .right, offset: start)); index += 1; expectingValue = false; continue }
            let rest = bytes[index...]
            let tag = (expectingValue || start > 0 && [9, 10, 13, 32].contains(bytes[start - 1])) && [43, 45].contains(bytes[index]) && index + 1 < bytes.count && ![9, 10, 13, 32, 40].contains(bytes[index + 1]) && !(48...57).contains(bytes[index + 1]) && bytes[index + 1] != 46
            if bytes[index] == 47 && expectingValue {
                index += 1
                while index < bytes.count {
                    if bytes[index] == 92, index + 1 < bytes.count { index += 2; continue }
                    if bytes[index] == 47 { index += 1; break }
                    index += 1
                }
                guard index > start + 1, bytes[index - 1] == 47 else { throw TaskFilterError.syntax("Unclosed /pattern/.", byteOffset: start) }
                result.append(Token(kind: .atom(String(decoding: bytes[start..<index], as: UTF8.self), false), offset: start)); expectingValue = false; continue
            }
            if !tag, let op = operators.first(where: { rest.starts(with: $0.utf8) }) {
                if op == "&&" || op == "||" { throw TaskFilterError.unsupported("Use ‘and’ or ‘or’; Taskwarrior 3.5 does not give symbolic aliases normal infix precedence.") }
                result.append(Token(kind: .op(op), offset: start)); index += op.utf8.count; expectingValue = true; continue
            }
            var value: [UInt8] = [], quoted = false, colon = false
            while index < bytes.count && ![9, 10, 13, 32, 40, 41].contains(bytes[index]) {
                let byte = bytes[index]
                if byte == 34 || byte == 39 {
                    value.append(byte)
                    quoted = true; index += 1
                    while index < bytes.count, bytes[index] != byte {
                        if bytes[index] == 92, index + 1 < bytes.count, bytes[index + 1] == byte { index += 1 }
                        value.append(bytes[index]); index += 1
                    }
                    guard index < bytes.count else { throw TaskFilterError.syntax("Unclosed quoted value.", byteOffset: start) }
                    value.append(byte); index += 1; continue
                }
                if byte == 58 { colon = true }
                if !colon && !tag && !value.isEmpty && [43, 45, 42, 47, 94, 37, 60, 62, 61, 33, 126, 38, 124].contains(byte) {
                    let candidate = String(decoding: bytes[start...].prefix { ![9, 10, 13, 32, 40, 41].contains($0) }, as: UTF8.self)
                    if schema.contains(candidate) || FilterScalar.isUUIDLiteral(candidate) || candidate.range(of: #"^[0-9]+(?:-[0-9]+|(?:,[0-9]+)+)$"#, options: .regularExpression) != nil || (try? FilterDateExpression(candidate)) != nil { value = Array(candidate.utf8); index = start + value.count }
                    break
                }
                value.append(byte); index += 1
            }
            guard index > start else { throw TaskFilterError.syntax("Unrecognized expression token.", byteOffset: start) }
            let atom = String(decoding: value, as: UTF8.self)
            if !quoted, ["and", "or", "xor"].contains(atom) { result.append(Token(kind: .op(atom), offset: start)); expectingValue = true }
            else { result.append(Token(kind: .atom(atom, quoted), offset: start)); expectingValue = false }
        }
        return result
    }
}
