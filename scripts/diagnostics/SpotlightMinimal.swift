import SwiftUI
import CoreSpotlight

@main
struct SpotlightMinimalApp: App {
    private let probe = SpotlightMinimal()

    var body: some Scene {
        WindowGroup {
            Text("Standalone Spotlight probe").onAppear { probe.start() }
        }
    }
}

final class SpotlightMinimal {
    private lazy var index = CSSearchableIndex(name: "tsk.tasks.v1", protectionClass: .completeUntilFirstUserAuthentication)
    private let namespace = "spotlight-minimal"
    private let identifier = UUID().uuidString
    private var query: CSSearchQuery?
    private var found: [String] = []
    private var events: [[String: Any]] = []
    private var finished = false

    private var started = false

    func start() {
        guard !started else { return }
        started = true
        record("launched", ["indexingAvailable": CSSearchableIndex.isIndexingAvailable()])
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) {
            self.finish(false, reason: "setup-timeout-120s")
        }
        index.deleteSearchableItems(withDomainIdentifiers: [namespace]) { error in
            DispatchQueue.main.async {
                self.record("delete-callback", ["error": error?.localizedDescription ?? ""])
                guard error == nil else { self.finish(false, reason: "delete-error"); return }
                self.indexItem()
            }
        }
    }

    private func indexItem() {
        let attributes = CSSearchableItemAttributeSet(itemContentType: "public.text")
        attributes.domainIdentifier = namespace
        attributes.title = "Spotlight minimal " + identifier
        attributes.displayName = attributes.title
        attributes.contentDescription = "One standalone searchable item"
        let item = CSSearchableItem(uniqueIdentifier: identifier, domainIdentifier: namespace, attributeSet: attributes)
        item.expirationDate = .distantFuture
        record("index-submission")
        index.indexSearchableItems([item]) { error in
            DispatchQueue.main.async {
                self.record("index-callback", ["error": error?.localizedDescription ?? ""])
                guard error == nil else { self.finish(false, reason: "index-error"); return }
                self.startQuery()
            }
        }
    }

    private func startQuery() {
        let query = CSSearchQuery(queryString: "domainIdentifier == \"\(namespace)\"", attributes: ["title"])
        self.query = query
        query.foundItemsHandler = { items in
            let identifiers = items.map(\.uniqueIdentifier)
            DispatchQueue.main.async {
                self.found += identifiers
                self.record("query-found", ["identifiers": identifiers])
            }
        }
        query.completionHandler = { error in
            DispatchQueue.main.async {
                self.record("query-completion", ["error": error?.localizedDescription ?? ""])
                self.finish(error == nil && self.found.contains(self.identifier), reason: "query-completed")
            }
        }
        record("query-start")
        query.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) {
            guard !self.finished else { return }
            self.finish(false, reason: "query-timeout-45s")
            query.cancel()
        }
    }

    private func record(_ event: String, _ details: [String: Any] = [:]) {
        guard !finished else { return }
        events.append(["event": event, "time": Date().timeIntervalSince1970, "details": details])
        writeResult(["status": "pending"])
    }

    private func finish(_ success: Bool, reason: String) {
        guard !finished else { return }
        finished = true
        writeResult(["status": success ? "passed" : "failed", "reason": reason])
    }

    private func writeResult(_ outcome: [String: Any]) {
        var result = outcome
        result["expectedIdentifier"] = identifier
        result["found"] = found
        result["events"] = events
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("result.json")
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
