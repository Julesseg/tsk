#if DEBUG && targetEnvironment(simulator)
import Foundation
import TskCore

@MainActor enum TaskCompletionDiagnostics {
    private static var recorder: Recorder?

    static func begin(store: TaskStore, task: TaskRecord, context: TaskCompletionFeedback.Context, animated: Bool) -> ((String, [String: String]) -> Void)? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["TSK_UI_ISOLATED_SIMULATOR"] == "1",
              let session = environment["TSK_UI_TEST_SESSION"].flatMap(UUID.init(uuidString:)),
              let replica = environment["TSK_TEST_REPLICA_NAME"].flatMap(UUID.init(uuidString:)),
              environment["TSK_TEST_COMPLETION_FEEDBACK_TRACE"].flatMap(UUID.init(uuidString:)) == replica else { return nil }
        if recorder == nil { recorder = Recorder(session: session.uuidString, replica: replica.uuidString) }
        guard let recorder, !recorder.expired, recorder.operations.count < 8 else { recorder?.dropped += 1; return nil }
        let id = UUID().uuidString
        recorder.operations[id] = Operation(store: store, taskID: task.id, context: context)
        recorder.record(id, "operation.installed", ["animated": String(animated)])
        return { [weak recorder] stage, fields in recorder?.record(id, stage, fields) }
    }

    @MainActor private final class Operation {
        weak var store: TaskStore?
        let storeID: String
        let feedbackID: String
        let taskID: UUID
        let context: TaskCompletionFeedback.Context

        init(store: TaskStore, taskID: UUID, context: TaskCompletionFeedback.Context) {
            self.store = store
            storeID = String(describing: ObjectIdentifier(store))
            feedbackID = String(describing: ObjectIdentifier(store.completionFeedback))
            self.taskID = taskID
            self.context = context
        }

        func snapshot() -> [String: String] {
            var fields = ["taskID": taskID.uuidString, "storeID": storeID, "feedbackID": feedbackID,
                          "capturedQuery": context.query.rawValue, "capturedProject": String(reflecting: context.project),
                          "capturedCustomView": context.customViewID?.uuidString ?? "nil", "capturedFilter": context.filter?.rawValue ?? "nil"]
            guard let store else { fields["storeReleased"] = "true"; return fields }
            let current = store.completionContext
            let editing = store.rowEditing
            let latest = store.tasks.first { $0.id == taskID }
            let visible = store.visibleTasks.first { $0.id == taskID }
            fields.merge([
                "storeReleased": "false", "currentQuery": current.query.rawValue,
                "currentProject": String(reflecting: current.project), "currentCustomView": current.customViewID?.uuidString ?? "nil",
                "currentFilter": current.filter?.rawValue ?? "nil", "contextMatches": String(current == context),
                "latestContains": String(latest != nil), "latestStatus": latest?.status ?? "nil",
                "allStatus": store.allTasks.first { $0.id == taskID }?.status ?? "nil",
                "visibleContains": String(visible != nil), "visibleStatus": visible?.status ?? "nil",
                "phase": store.completionFeedback.phase(for: taskID, context: context).map { String(describing: $0) } ?? "nil",
                "currentPhase": store.completionFeedback.phase(for: taskID, context: current).map { String(describing: $0) } ?? "nil",
                "rowEditingID": editing.map { String(describing: ObjectIdentifier($0)) } ?? "nil",
                "rowID": editing?.rowID ?? "nil", "rowEditingContextMatches": String(editing?.context == current),
                "rowEditingContains": String(editing?.tasks.contains { $0.id == taskID } == true),
                "visibleSource": editing?.context == current ? "rowEditing" : "feedbackAndLatest",
                "storeSaving": String(store.isSaving)
            ]) { _, new in new }
            return fields
        }
    }

    @MainActor private final class Recorder {
        let session: String
        let replica: String
        let processID = ProcessInfo.processInfo.processIdentifier
        let installedUptime = ProcessInfo.processInfo.systemUptime
        let exporter = CompletionExporter()
        var operations: [String: Operation] = [:]
        var events: [CompletionEvent] = []
        var sequence = 0
        var dropped = 0
        var checkpoints = 0
        var expired = false
        var firstCheckpointWallTime: Double?
        var timer: DispatchSourceTimer?

        init(session: String, replica: String) {
            self.session = session
            self.replica = replica
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + .milliseconds(500), repeating: .milliseconds(500), leeway: .milliseconds(50))
            timer.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.checkpoint() } }
            self.timer = timer
            timer.resume()
        }

        func record(_ operation: String, _ stage: String, _ fields: [String: String]) {
            guard !expired else { dropped += 1; return }
            sequence += 1
            guard events.count < 256 else { dropped += 1; return }
            let state = operations[operation]?.snapshot() ?? [:]
            events.append(CompletionEvent(sequence: sequence, operation: operation, stage: stage,
                                          wallTime: Date().timeIntervalSince1970, uptime: ProcessInfo.processInfo.systemUptime,
                                          fields: state.merging(fields) { _, new in new }))
        }

        func checkpoint() {
            let wallTime = Date().timeIntervalSince1970
            let uptime = ProcessInfo.processInfo.systemUptime
            if firstCheckpointWallTime == nil { firstCheckpointWallTime = wallTime }
            checkpoints += 1
            expired = uptime - installedUptime >= 180
            let packet = CompletionPacket(version: "completion-feedback-v1", session: session, replica: replica,
                processID: processID, installedUptime: installedUptime, firstCheckpointWallTime: firstCheckpointWallTime ?? wallTime,
                checkpointOrdinal: checkpoints, checkpointWallTime: wallTime, checkpointUptime: uptime,
                copiedThroughSequence: sequence, dropped: dropped, expired: expired,
                states: operations.mapValues { $0.snapshot() }, events: events)
            exporter.enqueue(packet)
            if expired { timer?.cancel(); timer = nil }
        }
    }
}

private struct CompletionEvent: Codable, Sendable {
    let sequence: Int
    let operation: String
    let stage: String
    let wallTime: Double
    let uptime: Double
    let fields: [String: String]
}

private struct CompletionPacket: Codable, Sendable {
    let version: String
    let session: String
    let replica: String
    let processID: Int32
    let installedUptime: Double
    let firstCheckpointWallTime: Double
    let checkpointOrdinal: Int
    let checkpointWallTime: Double
    let checkpointUptime: Double
    let copiedThroughSequence: Int
    let dropped: Int
    let expired: Bool
    let states: [String: [String: String]]
    let events: [CompletionEvent]
}

private struct CompletionExport: Codable {
    let observation: CompletionPacket
    let exportOrdinal: Int
    let exportFailures: Int
}

// Export state is confined to the utility queue.
private final class CompletionExporter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "tsk.completion-feedback-diagnostics", qos: .utility)
    private var ordinal = 0
    private var failures = 0

    func enqueue(_ packet: CompletionPacket) {
        queue.async { [self] in
            ordinal += 1
            do {
                let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("participant-fixture-pr77-completion-feedback-\(packet.replica)-\(packet.processID).json")
                let envelope = CompletionExport(observation: packet, exportOrdinal: ordinal, exportFailures: failures)
                try JSONEncoder().encode(envelope).write(to: file, options: .atomic)
            } catch { failures += 1 }
        }
    }
}
#endif
