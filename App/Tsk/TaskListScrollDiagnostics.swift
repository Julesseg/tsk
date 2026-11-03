#if DEBUG && targetEnvironment(simulator)
import Foundation

@MainActor enum TaskListScrollDiagnostics {
    private static var recorder: Recorder?

    static func install(_ environment: [String: String]) {
        guard recorder == nil, environment["TSK_UI_ISOLATED_SIMULATOR"] == "1",
              let session = environment["TSK_UI_TEST_SESSION"].flatMap(UUID.init(uuidString:)),
              let replica = environment["TSK_TEST_REPLICA_NAME"].flatMap(UUID.init(uuidString:)),
              environment["TSK_TEST_LIST_SCROLL_TRACE"].flatMap(UUID.init(uuidString:)) == replica else { return }
        recorder = Recorder(session: session.uuidString, replica: replica.uuidString)
    }

    static func entered(_ trigger: String, store: TaskStore) {
        guard let recorder else { return }
        let editing = store.rowEditing
        recorder.entered(trigger, store: String(describing: ObjectIdentifier(store)), query: String(describing: store.query),
                         rowID: editing?.rowID, editing: editing.map { String(describing: ObjectIdentifier($0)) })
    }

    static func prepare(_ site: String, target: UUID, anchor: String, store: TaskStore, editing: TaskRowEditing? = nil, viewport: CGRect? = nil, keyboardInset: CGFloat? = nil, animation: String) -> Request? {
        guard let recorder, !recorder.expired else { return nil }
        var fields = ["site": site, "target": target.uuidString, "anchor": anchor,
                      "store": String(describing: ObjectIdentifier(store)), "query": String(describing: store.query),
                      "animation": animation, "storeSaving": String(store.isSaving)]
        if let editing = editing ?? store.rowEditing {
            fields["rowID"] = editing.rowID
            fields["editing"] = String(describing: ObjectIdentifier(editing))
            fields["expanded"] = String(editing.isExpanded)
            fields["animating"] = String(editing.isAnimating)
            fields["editingSaving"] = String(editing.isSaving)
            fields["parameter"] = editing.parameter?.rawValue ?? "nil"
            fields["visibilityBounds"] = String(describing: editing.visibilityBounds)
        }
        if let viewport { fields["viewport"] = String(describing: viewport) }
        if let keyboardInset { fields["keyboardInset"] = String(describing: keyboardInset) }
        recorder.requests += 1
        recorder.pending = recorder.requests
        return Request(ordinal: recorder.requests, wallTime: Date().timeIntervalSince1970, uptime: ProcessInfo.processInfo.systemUptime, fields: fields)
    }

    static func returned(_ request: Request?) {
        guard let recorder, let request else { return }
        recorder.append("scroll.request.returned", fields: request.fields.merging([
            "requestOrdinal": String(request.ordinal), "requestWallTime": String(request.wallTime),
            "requestUptime": String(request.uptime)
        ]) { _, new in new })
        recorder.pending = nil
    }

    struct Request {
        let ordinal: Int
        let wallTime: Double
        let uptime: Double
        let fields: [String: String]
    }

    @MainActor private final class Recorder {
        let session: String
        let replica: String
        let processID = ProcessInfo.processInfo.processIdentifier
        let installedUptime = ProcessInfo.processInfo.systemUptime
        let exporter = Exporter()
        var timer: DispatchSourceTimer?
        var events: [ScrollEvent] = []
        var stores = Set<String>()
        var sequence = 0
        var entries = 0
        var requests = 0
        var pending: Int?
        var dropped = 0
        var checkpoints = 0
        var expired = false
        var lastEntry: [String: String]?
        var firstCheckpointUptime: Double?
        var firstCheckpointWallTime: Double?

        init(session: String, replica: String) {
            self.session = session
            self.replica = replica
            append("installed", fields: ["sites": "TaskListView.selection.today,TaskListView.selection.plain,TaskListView.revealEditor", "version": "list-scroll-v1"])
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + .milliseconds(500), repeating: .milliseconds(500), leeway: .milliseconds(50))
            timer.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.checkpoint() } }
            self.timer = timer
            timer.resume()
            checkpoint()
        }

        func entered(_ trigger: String, store: String, query: String, rowID: String?, editing: String?) {
            guard !expired else { return }
            entries += 1
            lastEntry = ["trigger": trigger, "store": store, "query": query,
                         "rowID": rowID ?? "nil", "editing": editing ?? "nil",
                         "entryOrdinal": String(entries), "uptime": String(ProcessInfo.processInfo.systemUptime),
                         "wallTime": String(Date().timeIntervalSince1970)]
            if !stores.contains(store) {
                guard stores.count < 8 else { dropped += 1; return }
                stores.insert(store)
                append("list.registered", fields: ["store": store, "query": query, "trigger": trigger])
            }
        }

        func append(_ stage: String, fields: [String: String]) {
            sequence += 1
            guard events.count < 256 else { dropped += 1; return }
            events.append(ScrollEvent(sequence: sequence, wallTime: Date().timeIntervalSince1970,
                                      uptime: ProcessInfo.processInfo.systemUptime, stage: stage, fields: fields))
        }

        func checkpoint() {
            checkpoints += 1
            let uptime = ProcessInfo.processInfo.systemUptime
            let wallTime = Date().timeIntervalSince1970
            if firstCheckpointUptime == nil {
                firstCheckpointUptime = uptime
                firstCheckpointWallTime = wallTime
            }
            expired = uptime - installedUptime >= 660
            let packet = ScrollPacket(session: session, replica: replica, processID: processID, installedUptime: installedUptime,
                                      firstCheckpointUptime: firstCheckpointUptime ?? uptime, firstCheckpointWallTime: firstCheckpointWallTime ?? wallTime,
                                      checkpointOrdinal: checkpoints, checkpointWallTime: wallTime,
                                      checkpointUptime: uptime, copiedThroughSequence: sequence, entryCount: entries,
                                      requestCount: requests, pendingRequestOrdinal: pending, dropped: dropped,
                                      exporterStopped: expired, lastEntry: lastEntry, events: events)
            exporter.enqueue(packet)
            if expired { timer?.cancel(); timer = nil }
        }
    }
}

private struct ScrollEvent: Codable, Sendable {
    let sequence: Int
    let wallTime: Double
    let uptime: Double
    let stage: String
    let fields: [String: String]
}

private struct ScrollPacket: Codable, Sendable {
    let session: String
    let replica: String
    let processID: Int32
    let installedUptime: Double
    let firstCheckpointUptime: Double
    let firstCheckpointWallTime: Double
    let checkpointOrdinal: Int
    let checkpointWallTime: Double
    let checkpointUptime: Double
    let copiedThroughSequence: Int
    let entryCount: Int
    let requestCount: Int
    let pendingRequestOrdinal: Int?
    let dropped: Int
    let exporterStopped: Bool
    let lastEntry: [String: String]?
    let events: [ScrollEvent]
}

private struct ScrollExport: Codable {
    let observation: ScrollPacket
    let exportOrdinal: Int
    let exportFailures: Int
}

// Export state is confined to the utility queue.
private final class Exporter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "tsk.list-scroll-diagnostics", qos: .utility)
    private var ordinal = 0
    private var failures = 0

    func enqueue(_ packet: ScrollPacket) {
        queue.async { [self] in
            ordinal += 1
            do {
                let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("participant-fixture-pr77-list-scroll-\(packet.replica)-\(packet.processID).json")
                let envelope = ScrollExport(observation: packet, exportOrdinal: ordinal, exportFailures: failures)
                try JSONEncoder().encode(envelope).write(to: file, options: .atomic)
            } catch { failures += 1 }
        }
    }
}
#endif
