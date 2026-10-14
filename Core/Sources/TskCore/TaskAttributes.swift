import Foundation

public struct UTF8String: RawRepresentable, Hashable, Comparable, Codable, Sendable, Identifiable {
    public let rawValue: String
    public var id: UTF8String { self }

    public init(_ value: String) { rawValue = value }
    public init(rawValue: String) { self.rawValue = rawValue }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue.utf8.elementsEqual(rhs.rawValue.utf8)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue.utf8.lexicographicallyPrecedes(rhs.rawValue.utf8)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue.utf8.count)
        for byte in rawValue.utf8 { hasher.combine(byte) }
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public protocol TaskAttributeValue: Codable, Equatable, Sendable {
    func matchesBytes(_ other: Self) -> Bool
}

extension String: TaskAttributeValue {
    public func matchesBytes(_ other: String) -> Bool { utf8.elementsEqual(other.utf8) }
}

extension Optional: TaskAttributeValue where Wrapped: TaskAttributeValue {
    public func matchesBytes(_ other: Self) -> Bool {
        switch (self, other) {
        case (.none, .none): true
        case (.some(let lhs), .some(let rhs)): lhs.matchesBytes(rhs)
        default: false
        }
    }
}

public struct TaskAttributeMap<Value: TaskAttributeValue>: Codable, Equatable, Sendable, ExpressibleByDictionaryLiteral, Sequence {
    public typealias Element = (key: String, value: Value)
    private var storage: [UTF8String: Value] = [:]

    public init() {}

    public init(dictionaryLiteral elements: (String, Value)...) {
        for (key, value) in elements { storage[UTF8String(key)] = value }
    }

    public init<S: Sequence>(_ elements: S) where S.Element == Element {
        for (key, value) in elements { storage[UTF8String(key)] = value }
    }

    public var count: Int { storage.count }
    public var isEmpty: Bool { storage.isEmpty }
    public var keyIdentities: [UTF8String] { storage.keys.sorted() }
    public var keys: [String] { keyIdentities.map(\.rawValue) }

    public subscript(key: String) -> Value? {
        get { storage[UTF8String(key)] }
        set { storage[UTF8String(key)] = newValue }
    }

    @discardableResult public mutating func updateValue(_ value: Value, forKey key: String) -> Value? {
        storage.updateValue(value, forKey: UTF8String(key))
    }

    @discardableResult public mutating func removeValue(forKey key: String) -> Value? {
        storage.removeValue(forKey: UTF8String(key))
    }

    public func makeIterator() -> IndexingIterator<[Element]> {
        keyIdentities.map { (key: $0.rawValue, value: storage[$0]!) }.makeIterator()
    }

    public func mapValues<T: TaskAttributeValue>(_ transform: (Value) throws -> T) rethrows -> TaskAttributeMap<T> {
        var result = TaskAttributeMap<T>()
        for (key, value) in self { result.updateValue(try transform(value), forKey: key) }
        return result
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return lhs.storage.allSatisfy { key, value in
            guard let other = rhs.storage[key] else { return false }
            return value.matchesBytes(other)
        }
    }

    public init(from decoder: any Decoder) throws {
        let entries = try decoder.singleValueContainer().decode([Entry].self)
        for entry in entries { storage[UTF8String(entry.key)] = entry.value }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(map { Entry(key: $0.key, value: $0.value) })
    }

    private struct Entry: Codable {
        let key: String
        let value: Value
    }
}

public typealias TaskAttributes = TaskAttributeMap<String>
public typealias TaskAttributePatch = TaskAttributeMap<String?>

extension TaskAttributeMap where Value == String {
    public func changes(comparedTo original: Self) -> TaskAttributePatch {
        var patch = TaskAttributePatch()
        for key in Set(keyIdentities).union(original.keyIdentities) {
            let edited = self[key.rawValue]
            if !edited.matchesBytes(original[key.rawValue]) {
                patch.updateValue(edited, forKey: key.rawValue)
            }
        }
        return patch
    }
}
