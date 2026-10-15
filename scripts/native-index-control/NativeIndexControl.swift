import UIKit
@preconcurrency import CoreSpotlight

struct Configuration: Encodable, Sendable {
    let token: String
    let protection: String
    let order: String
    let bundle: String

    init?() {
        let environment = ProcessInfo.processInfo.environment
        guard let raw = environment["TSK_INDEX_TOKEN"], let identifier = UUID(uuidString: raw),
              let protection = environment["TSK_INDEX_PROTECTION"], ["protected", "default-named"].contains(protection),
              let order = environment["TSK_INDEX_ORDER"], ["delete-first", "index-first"].contains(order),
              Bundle.main.bundleIdentifier == "com.julesseguin.tsk.native-index-control" else { return nil }
        token = identifier.uuidString
        self.protection = protection
        self.order = order
        bundle = Bundle.main.bundleIdentifier!
    }

    var domain: String { "tsk.native-control." + token }
    var item: String { domain + "/item" }
    var index: String { "tsk.native-control." + protection + "." + token }
}

struct NativeError: Encodable, Sendable {
    let domain: String
    let code: Int
    init?(_ error: (any Error)?) {
        guard let error = error as NSError? else { return nil }
        domain = String(error.domain.prefix(200))
        code = error.code
    }
}

struct Event: Encodable, Sendable {
    let stage: String
    let time = Date().timeIntervalSince1970
    let uptime = ProcessInfo.processInfo.systemUptime
    let mainThread = Thread.isMainThread
    var error: NativeError?
    var count: Int?
    var exactIdentity: Bool?
    var available: Bool?
    var heartbeatOrdinal: Int?
}

final class Recorder: @unchecked Sendable {
    struct Receipt: Encodable {
        let configuration: Configuration
        let domain: String
        let indexName: String
        let itemIdentifier: String
        let pid = ProcessInfo.processInfo.processIdentifier
        var outcome = "pending"
        var events: [Event] = []
    }
    private let lock = NSLock()
    private var receipt: Receipt
    init(_ configuration: Configuration) {
        receipt = Receipt(configuration: configuration, domain: configuration.domain,
                          indexName: configuration.index, itemIdentifier: configuration.item)
    }

    @discardableResult
    func record(_ event: Event, outcome: String? = nil) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard receipt.events.count < 64 else { return false }
        var candidate = receipt
        candidate.events.append(event)
        if let outcome { candidate.outcome = outcome }
        do {
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(candidate)
            guard data.count <= 65536 else {
                NSLog("TSK_NATIVE_INDEX_CONTROL receipt-write-failed")
                return false
            }
            try data.write(to: directory.appendingPathComponent("native-index-control.json"), options: .atomic)
            receipt = candidate
            return true
        } catch {
            NSLog("TSK_NATIVE_INDEX_CONTROL receipt-write-failed")
            return false
        }
    }
}

final class QueryMatches: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var exact = false
    private let expected: String
    init(expected: String) { self.expected = expected }
    func receive(_ items: [CSSearchableItem]) {
        lock.lock()
        defer { lock.unlock() }
        count += items.count
        exact = exact || items.contains { $0.uniqueIdentifier == expected }
    }
    func snapshot() -> (Int, Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (count, exact)
    }
}

actor NativeControl {
    private let configuration: Configuration
    private let recorder: Recorder
    private let index: CSSearchableIndex
    private var queries: [CSSearchQuery] = []
    private var mismatch = false
    private var started = false

    init(_ configuration: Configuration, recorder: Recorder) {
        self.configuration = configuration
        self.recorder = recorder
        if configuration.protection == "protected" {
            index = CSSearchableIndex(name: configuration.index, protectionClass: .completeUntilFirstUserAuthentication)
        } else {
            index = CSSearchableIndex(name: configuration.index)
        }
    }

    func start() {
        guard !started else { return }
        started = true
        recorder.record(Event(stage: "index.availability", available: CSSearchableIndex.isIndexingAvailable()))
        if configuration.order == "delete-first" { remove(initial: true) }
        else { insert() }
    }

    private func remove(initial: Bool) {
        let stage = initial ? "initial-delete" : "cleanup-delete"
        let recorder = recorder
        recorder.record(Event(stage: stage + ".submit"))
        index.deleteSearchableItems(withDomainIdentifiers: [configuration.domain]) { @Sendable [self] error in
            let failure = NativeError(error)
            recorder.record(Event(stage: stage + ".callback", error: failure))
            Task { await self.removed(initial: initial, error: failure) }
        }
        recorder.record(Event(stage: stage + ".returned"))
    }

    private func removed(initial: Bool, error: NativeError?) {
        guard error == nil else { finish("api-error"); return }
        if initial { insert() } else { query(inserted: false) }
    }

    private func insert() {
        let attributes = CSSearchableItemAttributeSet(itemContentType: "public.text")
        attributes.title = "Owned native control " + configuration.token
        let item = CSSearchableItem(uniqueIdentifier: configuration.item, domainIdentifier: configuration.domain,
                                    attributeSet: attributes)
        item.expirationDate = .distantFuture
        let recorder = recorder
        recorder.record(Event(stage: "index.submit"))
        index.indexSearchableItems([item]) { @Sendable [self] error in
            let failure = NativeError(error)
            recorder.record(Event(stage: "index.callback", error: failure))
            Task { await self.inserted(error: failure) }
        }
        recorder.record(Event(stage: "index.returned"))
    }

    private func inserted(error: NativeError?) {
        guard error == nil else { finish("api-error"); return }
        query(inserted: true)
    }

    private func query(inserted: Bool) {
        let stage = inserted ? "inserted-query" : "empty-query"
        let context = CSSearchQueryContext()
        context.fetchAttributes = []
        let query = CSSearchQuery(queryString: "domainIdentifier == \"" + configuration.domain + "\"", queryContext: context)
        queries.append(query)
        let matches = QueryMatches(expected: configuration.item)
        let recorder = recorder
        query.foundItemsHandler = { @Sendable items in matches.receive(items) }
        query.completionHandler = { @Sendable [self] error in
            let failure = NativeError(error)
            let (count, exact) = matches.snapshot()
            recorder.record(Event(stage: stage + ".callback", error: failure, count: count, exactIdentity: exact))
            Task { await self.queried(inserted: inserted, error: failure, count: count, exact: exact) }
        }
        recorder.record(Event(stage: stage + ".submit"))
        query.start()
        recorder.record(Event(stage: stage + ".returned"))
    }

    private func queried(inserted: Bool, error: NativeError?, count: Int, exact: Bool) {
        guard error == nil else { finish("api-error"); return }
        mismatch = mismatch || (inserted ? count != 1 || !exact : count != 0 || exact)
        if inserted { remove(initial: false) }
        else { finish(mismatch ? "query-mismatch" : "completed") }
    }

    private func finish(_ outcome: String) {
        recorder.record(Event(stage: "observation.finished"), outcome: outcome)
    }
}

@main
final class NativeIndexControlApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var control: NativeControl?
    private var heartbeat: Task<Void, Never>?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        guard let configuration = Configuration() else { return false }
        let recorder = Recorder(configuration)
        recorder.record(Event(stage: "protected-data.availability", available: application.isProtectedDataAvailable))
        let control = NativeControl(configuration, recorder: recorder)
        self.control = control
        let controller = UIViewController()
        controller.view.backgroundColor = .systemBackground
        let label = UILabel(frame: CGRect(x: 20, y: 100, width: 340, height: 120))
        label.numberOfLines = 0
        label.text = "Supplemental native index control\n" + configuration.protection + " / " + configuration.order
        controller.view.addSubview(label)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        heartbeat = Task { @MainActor in
            for ordinal in 1...24 {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                guard recorder.record(Event(stage: "app.main-actor.heartbeat", heartbeatOrdinal: ordinal)) else { return }
            }
        }
        Task { await control.start() }
        return true
    }
}
