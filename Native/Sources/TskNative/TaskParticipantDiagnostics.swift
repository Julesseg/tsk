import Foundation

public enum TaskParticipantDiagnostics {
    @TaskLocal public static var shareRequest: UUID?

    public static func begin(_ stage: String) -> UUID? {
        #if DEBUG && targetEnvironment(simulator)
        TaskParticipantDiagnosticRecorder.shared.begin(stage, token: environmentToken, request: shareRequest)
        #else
        nil
        #endif
    }

    public static func event(_ stage: String, details: [String: String]) {
        #if DEBUG && targetEnvironment(simulator)
        TaskParticipantDiagnosticRecorder.shared.event(stage, token: environmentToken, request: shareRequest, details: details)
        #endif
    }

    public static func beginShareRequest(_ request: UUID) {
        #if DEBUG && targetEnvironment(simulator)
        TaskParticipantDiagnosticRecorder.shared.beginRequest(request)
        #endif
    }

    public static func endShareRequest(_ request: UUID) {
        #if DEBUG && targetEnvironment(simulator)
        TaskParticipantDiagnosticRecorder.shared.finishRequest(request)
        #endif
    }

    public static func enableShareFixture(_ token: UUID, request: UUID) {
        #if DEBUG && targetEnvironment(simulator)
        guard Bundle.main.bundleIdentifier == "com.julesseguin.tsk.share",
              let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.julesseguin.tsk") else { return }
        TaskParticipantDiagnosticRecorder.shared.enableShare(token: token, request: request, directory: group.appendingPathComponent("UITestDiagnostics"))
        event("share.fixture.loaded", details: ["bundle": "com.julesseguin.tsk.share"])
        #endif
    }

    #if DEBUG && targetEnvironment(simulator)
    private static var environmentToken: String? {
        guard let token = ProcessInfo.processInfo.environment["TSK_TEST_REPLICA_NAME"], !token.isEmpty else { return nil }
        return token
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
    private var sharedDirectory: URL?
    private var shareToken: String?
    private var request: UUID?

    func beginRequest(_ request: UUID) {
        lock.lock()
        defer { lock.unlock() }
        reset()
        self.request = request
    }

    func finishRequest(_ request: UUID) {
        lock.lock()
        defer { lock.unlock() }
        if self.request == request { reset() }
    }

    private func reset() {
        request = nil
        shareToken = nil
        sharedDirectory = nil
        events = []
        active = [:]
        activeTokens = [:]
    }

    func enableShare(token: UUID, request: UUID, directory: URL) {
        lock.lock()
        defer { lock.unlock() }
        guard self.request == request else { return }
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

    func begin(_ stage: String, token: String? = nil, request: UUID? = nil) -> UUID? {
        lock.lock()
        defer { lock.unlock() }
        guard let token = resolve(token: token, request: request) else { return nil }
        let id = UUID()
        record(stage, phase: "begin", id: id, token: token)
        return id
    }

    func event(_ stage: String, token: String? = nil, request: UUID? = nil, details: [String: String]) {
        lock.lock()
        defer { lock.unlock() }
        guard let token = resolve(token: token, request: request) else { return }
        record(stage, phase: "event", id: UUID(), token: token, details: details)
    }

    func end(_ stage: String, id: UUID?) {
        lock.lock()
        defer { lock.unlock() }
        guard let id, let started = active[id], let token = activeTokens[id] else { return }
        record(started.stage, phase: "end", id: id, token: token)
    }

    private func resolve(token: String?, request: UUID?) -> String? {
        if let request { return self.request == request ? shareToken : nil }
        guard self.request == nil else { return nil }
        return token
    }

    private var activeTokens: [UUID: String] = [:]

    private func record(_ stage: String, phase: String, id: UUID, token: String, details: [String: String]? = nil) {
        let event = Event(stage: stage, phase: phase, id: id, time: Date().timeIntervalSince1970, processID: ProcessInfo.processInfo.processIdentifier, details: details)
        events.append(event)
        if phase == "begin" { active[id] = event; activeTokens[id] = token }
        else { active[id] = nil; activeTokens[id] = nil }
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
