import Foundation

public enum TaskParticipantDiagnostics {
    public static func begin(_ stage: String) -> UUID? {
        #if DEBUG && targetEnvironment(simulator)
        guard let token = scopeToken else { return nil }
        let id = UUID()
        TaskParticipantDiagnosticRecorder.shared.record(stage, phase: "begin", id: id, token: token)
        return id
        #else
        return nil
        #endif
    }

    public static func event(_ stage: String, details: [String: String]) {
        #if DEBUG && targetEnvironment(simulator)
        guard let token = scopeToken else { return }
        TaskParticipantDiagnosticRecorder.shared.record(stage, phase: "event", id: UUID(), token: token, details: details)
        #endif
    }

    public static func enableShareFixture(_ token: UUID) {
        #if DEBUG && targetEnvironment(simulator)
        guard Bundle.main.bundleIdentifier == "com.julesseguin.tsk.share",
              let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.julesseguin.tsk") else { return }
        TaskParticipantDiagnosticRecorder.shared.enableShare(token: token, directory: group.appendingPathComponent("UITestDiagnostics"))
        event("share.fixture.loaded", details: ["bundle": "com.julesseguin.tsk.share"])
        #endif
    }

    #if DEBUG && targetEnvironment(simulator)
    private static var scopeToken: String? {
        if let token = ProcessInfo.processInfo.environment["TSK_TEST_REPLICA_NAME"], !token.isEmpty { return token }
        return TaskParticipantDiagnosticRecorder.shared.shareScope
    }
    #endif

    public static func end(_ stage: String, id: UUID?) {
        #if DEBUG && targetEnvironment(simulator)
        guard let id, let token = scopeToken else { return }
        TaskParticipantDiagnosticRecorder.shared.record(stage, phase: "end", id: id, token: token)
        #endif
    }
}

#if DEBUG && targetEnvironment(simulator)
private final class TaskParticipantDiagnosticRecorder: @unchecked Sendable {
    static let shared = TaskParticipantDiagnosticRecorder()
    private let lock = NSLock()
    private var events: [Event] = []
    private var active: [UUID: Event] = [:]
    private var sharedDirectory: URL?
    private var shareToken: String?

    var shareScope: String? {
        lock.lock()
        defer { lock.unlock() }
        return shareToken
    }

    func enableShare(token: UUID, directory: URL) {
        lock.lock()
        defer { lock.unlock() }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            sharedDirectory = directory
            shareToken = "share-" + token.uuidString
        } catch { NSLog("tsk isolated Share diagnostic failed: %@", error.localizedDescription) }
    }

    private struct Event: Codable {
        let stage: String
        let phase: String
        let id: UUID
        let time: TimeInterval
        let processID: Int32
        let details: [String: String]?
    }

    func record(_ stage: String, phase: String, id: UUID, token: String, details: [String: String]? = nil) {
        lock.lock()
        defer { lock.unlock() }
        let event = Event(stage: stage, phase: phase, id: id, time: Date().timeIntervalSince1970, processID: ProcessInfo.processInfo.processIdentifier, details: details)
        events.append(event)
        if phase == "begin" { active[id] = event }
        else { active[id] = nil }
        events = Array(events.suffix(300))
        let name = token.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "-" ? String($0) : "_" }.joined()
        do {
            let data = try JSONEncoder().encode(["events": events, "active": active.values.sorted { $0.time < $1.time }])
            let destination = sharedDirectory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let file = destination.appendingPathComponent("participant-fixture-\(name)-\(ProcessInfo.processInfo.processIdentifier).json")
            try data.write(to: file, options: .atomic)
        } catch { NSLog("tsk isolated participant diagnostic failed: %@", error.localizedDescription) }
    }
}
#endif
