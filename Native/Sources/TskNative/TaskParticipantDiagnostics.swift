import Foundation

public enum TaskParticipantDiagnostics {
    public static var isEnabled: Bool {
        #if DEBUG && targetEnvironment(simulator)
        environmentToken != nil
        #else
        false
        #endif
    }

    public static func begin(_ stage: String) -> UUID? {
        #if DEBUG && targetEnvironment(simulator)
        TaskParticipantDiagnosticRecorder.shared.begin(stage, token: environmentToken)
        #else
        nil
        #endif
    }

    public static func event(_ stage: String, details: [String: String]) {
        #if DEBUG && targetEnvironment(simulator)
        TaskParticipantDiagnosticRecorder.shared.event(stage, token: environmentToken, details: details)
        #endif
    }

    #if DEBUG && targetEnvironment(simulator)
    private static var environmentToken: String? {
        TaskDiagnosticSettings.token(environment: ProcessInfo.processInfo.environment)
    }
    #endif

    public static func end(_ stage: String, id: UUID?) {
        #if DEBUG && targetEnvironment(simulator)
        TaskParticipantDiagnosticRecorder.shared.end(stage, id: id)
        #endif
    }
}

#if DEBUG
final class TaskParticipantDiagnosticRecorder: @unchecked Sendable {
    static let shared = TaskParticipantDiagnosticRecorder()
    private let lock = NSLock()
    private var events: [Event] = []
    private var active: [UUID: Event] = [:]
    private struct Event: Codable, Sendable {
        let stage: String
        let phase: String
        let id: UUID
        let time: TimeInterval
        let processID: Int32
        let details: [String: String]?
    }

    func begin(_ stage: String, token: String? = nil) -> UUID? {
        lock.lock()
        defer { lock.unlock() }
        guard let token else { return nil }
        let id = UUID()
        record(stage, phase: "begin", id: id, token: token)
        return id
    }

    func event(_ stage: String, token: String? = nil, details: [String: String]) {
        lock.lock()
        defer { lock.unlock() }
        guard let token else { return }
        record(stage, phase: "event", id: UUID(), token: token, details: details)
    }

    func end(_ stage: String, id: UUID?) {
        lock.lock()
        defer { lock.unlock() }
        guard let id, let started = active[id], let token = activeTokens[id] else { return }
        record(started.stage, phase: "end", id: id, token: token)
    }

    private var activeTokens: [UUID: String] = [:]

    private func record(_ stage: String, phase: String, id: UUID, token: String, details: [String: String]? = nil) {
        let event = Event(stage: stage, phase: phase, id: id, time: Date().timeIntervalSince1970, processID: ProcessInfo.processInfo.processIdentifier, details: details)
        events.append(event)
        if phase == "begin" { active[id] = event; activeTokens[id] = token }
        else { active[id] = nil; activeTokens[id] = nil }
        events = Array(events.suffix(300))
        let name = token.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "-" ? String($0) : "_" }.joined()
        let snapshot = ["events": events, "active": active.values.sorted { $0.time < $1.time }]
        let destination = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let file = destination.appendingPathComponent("participant-fixture-\(name)-\(ProcessInfo.processInfo.processIdentifier).json")
        TaskDiagnosticFileWriter.shared.submit(snapshot, to: file)
    }
}
#endif
