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
        #if os(iOS)
        index = CSSearchableIndex(name: indexName, protectionClass: .completeUntilFirstUserAuthentication)
        #else
        index = CSSearchableIndex(name: indexName)
        #endif
    }

    public func replace(_ items: [TaskSpotlightItem]) async throws {
        let available = CSSearchableIndex.isIndexingAvailable()
        TaskParticipantDiagnostics.event("spotlight.availability", details: ["available": String(available)])
        guard available else { throw SpotlightIndexError.unavailable }
        for item in items { guard (try? TaskSpotlightItem.taskID(from: item.identifier, namespace: namespace)) == item.taskID else { throw SpotlightIndexError.foreignItem } }
        let deletion = TaskParticipantDiagnostics.begin("spotlight.delete")
        do {
            defer { TaskParticipantDiagnostics.end("spotlight.delete", id: deletion) }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let submission = TaskParticipantDiagnostics.begin("spotlight.delete.submit")
                defer { TaskParticipantDiagnostics.end("spotlight.delete.submit", id: submission) }
                TaskParticipantDiagnostics.event("spotlight.delete.submission", details: ["mainThread": String(Thread.isMainThread)])
                index.deleteSearchableItems(withDomainIdentifiers: [namespace], completionHandler: Self.indexCompletion(stage: "spotlight.delete.callback", continuation: continuation))
            }
        }
        let values = items.map { item in
            let attributes = CSSearchableItemAttributeSet(itemContentType: "public.text")
            attributes.domainIdentifier = namespace
            attributes.title = item.title; attributes.displayName = item.title; attributes.contentDescription = item.summary
            let value = CSSearchableItem(uniqueIdentifier: item.identifier, domainIdentifier: namespace, attributeSet: attributes)
            value.expirationDate = .distantFuture
            return value
        }
        let indexing = TaskParticipantDiagnostics.begin("spotlight.index")
        defer { TaskParticipantDiagnostics.end("spotlight.index", id: indexing) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let submission = TaskParticipantDiagnostics.begin("spotlight.index.submit")
            defer { TaskParticipantDiagnostics.end("spotlight.index.submit", id: submission) }
            TaskParticipantDiagnostics.event("spotlight.index.submission", details: ["mainThread": String(Thread.isMainThread), "count": String(values.count)])
            index.indexSearchableItems(values, completionHandler: Self.indexCompletion(stage: "spotlight.index.callback", continuation: continuation))
        }
    }

    nonisolated private static func indexCompletion(stage: String, continuation: CheckedContinuation<Void, any Error>) -> @Sendable ((any Error)?) -> Void {
        { error in
            var details = ["mainThread": String(Thread.isMainThread), "succeeded": String(error == nil)]
            if let error {
                let native = error as NSError
                details["errorDomain"] = native.domain
                details["errorCode"] = String(native.code)
                details["error"] = native.localizedDescription
            }
            TaskParticipantDiagnostics.event(stage, details: details)
            if let error { continuation.resume(throwing: error) }
            else { continuation.resume() }
        }
    }

    public func query() async throws -> [SpotlightIndexedItem] {
        let query = CSSearchQuery(queryString: "domainIdentifier == \"\(Self.escaped(namespace))\"", attributes: ["title"])
        let id = UUID(), collector = SpotlightQueryCollector()
        let trace = TaskParticipantDiagnostics.begin("spotlight.query")
        if let trace { TaskParticipantDiagnostics.event("spotlight.query.invocation", details: ["queryID": id.uuidString, "spanID": trace.uuidString]) }
        activeQueries[id] = query
        defer { activeQueries[id] = nil; TaskParticipantDiagnostics.end("spotlight.query", id: trace) }
        return try await withCheckedThrowingContinuation { continuation in
            query.foundItemsHandler = Self.foundHandler(collector, queryID: id)
            query.completionHandler = Self.completionHandler(collector, continuation, queryID: id)
            let submission = TaskParticipantDiagnostics.begin("spotlight.query.submit")
            defer { TaskParticipantDiagnostics.end("spotlight.query.submit", id: submission) }
            if let submission { TaskParticipantDiagnostics.event("spotlight.query.submission", details: ["queryID": id.uuidString, "spanID": submission.uuidString, "mainThread": String(Thread.isMainThread)]) }
            query.start()
        }
    }

    nonisolated private static func foundHandler(_ collector: SpotlightQueryCollector, queryID: UUID) -> @Sendable ([CSSearchableItem]) -> Void {
        { items in
            collector.append(items.map { SpotlightIndexedItem(identifier: $0.uniqueIdentifier, title: $0.attributeSet.title ?? "") })
            TaskParticipantDiagnostics.event("spotlight.query.found", details: ["queryID": queryID.uuidString, "count": String(items.count), "mainThread": String(Thread.isMainThread)])
        }
    }
    nonisolated private static func completionHandler(_ collector: SpotlightQueryCollector, _ continuation: CheckedContinuation<[SpotlightIndexedItem], any Error>, queryID: UUID) -> @Sendable ((any Error)?) -> Void {
        { error in
            let receivedAt = Date().timeIntervalSince1970
            if let error { continuation.resume(throwing: error) }
            else { continuation.resume(returning: collector.values()) }
            var details = ["queryID": queryID.uuidString, "receivedAt": String(receivedAt), "succeeded": String(error == nil), "mainThread": String(Thread.isMainThread)]
            if let error {
                let native = error as NSError
                details["errorDomain"] = native.domain
                details["errorCode"] = String(native.code)
                details["error"] = native.localizedDescription
            }
            TaskParticipantDiagnostics.event("spotlight.query.callback", details: details)
        }
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
