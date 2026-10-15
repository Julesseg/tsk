#if canImport(CoreSpotlight)
import Foundation
@preconcurrency import CoreSpotlight
import TskCore

public enum SpotlightIndexError: Error, LocalizedError, Sendable {
    case unavailable, foreignItem
    public var errorDescription: String? {
        switch self {
        case .unavailable: "Spotlight indexing is unavailable on this device. Tasks are still saved."
        case .foreignItem: "A Spotlight update contained an item outside this task library."
        }
    }
}

public struct SpotlightIndexedItem: Equatable, Sendable {
    public let identifier: String
    public let title: String
}

@available(iOS 17.0, macOS 14.0, *)
public actor CoreSpotlightTaskIndex: TaskSpotlightIndex {
    public nonisolated let namespace: String
    private let index: CSSearchableIndex
    private var activeQueries: [UUID: CSSearchQuery] = [:]

    public init(namespace: String, indexName: String = "tsk.tasks.v1") {
        self.namespace = namespace
        index = CSSearchableIndex(name: indexName)
    }

    public func replace(_ items: [TaskSpotlightItem]) async throws {
        guard CSSearchableIndex.isIndexingAvailable() else { throw SpotlightIndexError.unavailable }
        for item in items { guard (try? TaskSpotlightItem.taskID(from: item.identifier, namespace: namespace)) == item.taskID else { throw SpotlightIndexError.foreignItem } }
        try await index.deleteSearchableItems(withDomainIdentifiers: [namespace])
        let values = items.map { item in
            let attributes = CSSearchableItemAttributeSet(itemContentType: "public.text")
            attributes.title = item.title; attributes.displayName = item.title; attributes.contentDescription = item.summary
            let value = CSSearchableItem(uniqueIdentifier: item.identifier, domainIdentifier: namespace, attributeSet: attributes)
            value.expirationDate = .distantFuture
            return value
        }
        try await index.indexSearchableItems(values)
    }

    public func query() async throws -> [SpotlightIndexedItem] {
        let query = CSSearchQuery(queryString: "domainIdentifier == \"\(Self.escaped(namespace))\"", attributes: ["title"])
        let id = UUID(), collector = SpotlightQueryCollector()
        activeQueries[id] = query
        defer { activeQueries[id] = nil }
        return try await withCheckedThrowingContinuation { continuation in
            query.foundItemsHandler = Self.foundHandler(collector)
            query.completionHandler = { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: collector.values()) }
            }
            query.start()
        }
    }

    nonisolated private static func foundHandler(_ collector: SpotlightQueryCollector) -> @Sendable ([CSSearchableItem]) -> Void {
        { items in collector.append(items.map { SpotlightIndexedItem(identifier: $0.uniqueIdentifier, title: $0.attributeSet.title ?? "") }) }
    }
    nonisolated private static func escaped(_ raw: String) -> String { raw.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
}

private final class SpotlightQueryCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [SpotlightIndexedItem] = []
    func append(_ values: [SpotlightIndexedItem]) { lock.lock(); defer { lock.unlock() }; items += values }
    func values() -> [SpotlightIndexedItem] { lock.lock(); defer { lock.unlock() }; return items.sorted { $0.identifier < $1.identifier } }
}
#endif
