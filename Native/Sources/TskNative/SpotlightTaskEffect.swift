#if canImport(CoreSpotlight)
import Foundation
import TskCore

public struct TaskSpotlightIndexStatus: Codable, Equatable, Sendable {
    public let indexedCount: Int?
    public let lastSuccessfulIndex: Date?
    public let error: String?
    public let pending: Bool
}

public enum TaskSpotlightExecution: Sendable {
    case automatic, participant, ownedWorker(String)
}

@available(iOS 17.0, macOS 14.0, *)
public struct SpotlightTaskEffect: Sendable {
    public static let containingAppOwner = "com.julesseguin.tsk"
    public let directory: URL
    private let index: (any TaskSpotlightIndex)?
    private let execution: TaskSpotlightExecution

    public init(directory: URL, index: (any TaskSpotlightIndex)? = nil, execution: TaskSpotlightExecution = .automatic) {
        self.directory = directory.resolvingSymlinksInPath().standardizedFileURL
        self.index = index
        self.execution = execution
    }

    public static func namespace(directory: URL) -> String {
        let parent = directory.deletingLastPathComponent()
        if parent.deletingLastPathComponent().lastPathComponent == "UITests" { return "com-julesseguin-tsk-tasks-test-" + parent.lastPathComponent }
        return "com-julesseguin-tsk-tasks-v1"
    }

    public func reconcile(manager: TaskManager, force: Bool = true) async -> TaskSpotlightIndexStatus {
        await enqueue(manager: manager, force: force)
    }

    public static func status(directory: URL, owner: String = containingAppOwner) throws -> TaskSpotlightIndexStatus {
        try SpotlightWorkStore(directory: directory).status(owner: owner)
    }

    private func enqueue(manager: TaskManager, force: Bool) async -> TaskSpotlightIndexStatus {
        let owner: String
        let runsWorker: Bool
        switch execution {
        case .automatic:
            owner = Self.containingAppOwner
            runsWorker = Bundle.main.bundleIdentifier == owner
        case .participant:
            owner = Self.containingAppOwner
            runsWorker = false
        case .ownedWorker(let identity):
            owner = identity
            runsWorker = true
        }
        let store = SpotlightWorkStore(directory: directory)
        do {
            guard !owner.isEmpty else { throw TaskManagementError.storage("Spotlight worker ownership is unavailable.") }
            let status = try await store.request(manager: manager, owner: owner, force: force)
            if runsWorker {
                await SpotlightWorkers.shared.request(directory: directory, owner: owner, manager: manager, index: index)
            }
            return status
        } catch {
            await store.recordWarning(error.localizedDescription)
            return TaskSpotlightIndexStatus(indexedCount: nil, lastSuccessfulIndex: nil, error: error.localizedDescription, pending: true)
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
extension SpotlightTaskEffect: TaskPostCommitEffect {
    public func apply(to manager: TaskManager, origin: TaskChangeOrigin) async { _ = await enqueue(manager: manager, force: false) }
}

private struct SpotlightAttempt: Codable, Equatable, Sendable {
    let id: UUID
    let owner: String
    let revision: UUID
    let request: UUID?
    let started: Date
}

private struct SpotlightWorkState: Codable, Equatable, Sendable {
    var requestedRevision: UUID?
    var requestedRepair: UUID?
    var confirmedRevision: UUID?
    var confirmedRepair: UUID?
    var confirmedOwner: String?
    var indexedCount: Int?
    var lastSuccessfulIndex: Date?
    var error: String?
    var attempt: SpotlightAttempt?

    func status(revision: UUID?, owner: String) -> TaskSpotlightIndexStatus {
        TaskSpotlightIndexStatus(indexedCount: indexedCount, lastSuccessfulIndex: lastSuccessfulIndex, error: error,
            pending: confirmedOwner != owner || confirmedRevision != revision || confirmedRepair != requestedRepair || attempt != nil || error != nil)
    }
}

private struct SpotlightWorkStore: Sendable {
    let directory: URL
    private var file: URL { directory.appendingPathComponent("spotlight-status.json") }
    private var warning: URL { directory.appendingPathComponent("spotlight-enqueue-error.txt") }

    func acquire() async throws -> any TaskMutationLease {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try await NativeMutationLease.acquire(path: directory.appendingPathComponent(".tsk-spotlight-state").path)
    }

    func load() throws -> SpotlightWorkState {
        do { return try JSONDecoder().decode(SpotlightWorkState.self, from: Data(contentsOf: file)) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return SpotlightWorkState() }
    }

    func save(_ state: SpotlightWorkState) throws {
        let data = try JSONEncoder().encode(state)
        #if os(iOS)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: file, options: .atomic)
        #endif
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    func status(owner: String) throws -> TaskSpotlightIndexStatus {
        let message = try readWarning()
        do {
            let state = try load()
            let revision = FileManager.default.fileExists(atPath: directory.appendingPathComponent("participant-changes.json").path)
                ? try LocalTaskChangeStore.read(directory).tasks : state.requestedRevision
            let status = state.status(revision: revision, owner: owner)
            return TaskSpotlightIndexStatus(indexedCount: status.indexedCount, lastSuccessfulIndex: status.lastSuccessfulIndex, error: message ?? status.error, pending: message != nil || status.pending)
        } catch {
            if let message { return TaskSpotlightIndexStatus(indexedCount: nil, lastSuccessfulIndex: nil, error: message, pending: true) }
            throw error
        }
    }

    func request(manager: TaskManager, owner: String, force: Bool) async throws -> TaskSpotlightIndexStatus {
        let lease = try await acquire()
        defer { lease.release() }
        let revision = try await manager.changeVersion().tasks
        var state = try load()
        state.requestedRevision = revision
        if force { state.requestedRepair = UUID() }
        try save(state)
        return state.status(revision: revision, owner: owner)
    }

    func recordWarning(_ message: String) async {
        do {
            let lease = try await acquire()
            defer { lease.release() }
            do {
                var state = try load()
                state.requestedRepair = UUID()
                state.error = message
                try save(state)
            } catch { NSLog("tsk Spotlight work metadata remains unreadable: %@", error.localizedDescription) }
            try Data(message.utf8).write(to: warning, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: warning.path)
        } catch { NSLog("tsk Spotlight request could not be persisted: %@", error.localizedDescription) }
    }

    func clearWarning() throws {
        if FileManager.default.fileExists(atPath: warning.path) { try FileManager.default.removeItem(at: warning) }
    }

    private func readWarning() throws -> String? {
        do { return try String(contentsOf: warning, encoding: .utf8) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
    }
}

@available(iOS 17.0, macOS 14.0, *)
private actor SpotlightWorkers {
    static let shared = SpotlightWorkers()
    private var workers: [String: SpotlightWorker] = [:]

    func request(directory: URL, owner: String, manager: TaskManager, index: (any TaskSpotlightIndex)?) async {
        let key = directory.path + "/" + owner
        let worker: SpotlightWorker
        if let existing = workers[key] { worker = existing }
        else {
            worker = SpotlightWorker(directory: directory, owner: owner, index: index ?? CoreSpotlightTaskIndex(namespace: SpotlightTaskEffect.namespace(directory: directory)))
            workers[key] = worker
        }
        await worker.request(manager: manager)
    }
}

@available(iOS 17.0, macOS 14.0, *)
private actor SpotlightWorker {
    private let directory: URL
    private let owner: String
    private let index: any TaskSpotlightIndex
    private var manager: TaskManager?
    private var generation = 0
    private var running: Task<Void, Never>?

    init(directory: URL, owner: String, index: any TaskSpotlightIndex) {
        self.directory = directory
        self.owner = owner
        self.index = index
    }

    func request(manager: TaskManager) {
        self.manager = manager
        generation += 1
        if running == nil { running = Task { await drain() } }
    }

    private func drain() async {
        let store = SpotlightWorkStore(directory: directory)
        var observedGeneration = generation
        var attemptID: UUID?
        var operationLease: (any TaskMutationLease)?
        var admissionState: SpotlightWorkState?
        defer { operationLease?.release() }
        let trace = TaskParticipantDiagnostics.begin("spotlight.reconcile")
        defer { TaskParticipantDiagnostics.end("spotlight.reconcile", id: trace) }
        do {
            let initial = try await store.acquire()
            do {
                defer { initial.release() }
                admissionState = try store.load()
            }
            let admission = TaskParticipantDiagnostics.begin("spotlight.admission")
            let lease: any TaskMutationLease
            do {
                defer { TaskParticipantDiagnostics.end("spotlight.admission", id: admission) }
                lease = try await NativeMutationLease.acquire(path: directory.appendingPathComponent(".tsk-spotlight-index").path)
            }
            operationLease = lease
            while let manager {
                observedGeneration = generation
                let stateLease = try await store.acquire()
                let target: SpotlightAttempt
                do {
                    defer { stateLease.release() }
                    let revision = try await manager.changeVersion().tasks
                    var state = try store.load()
                    state.requestedRevision = revision
                    guard state.status(revision: revision, owner: owner).pending else { break }
                    target = SpotlightAttempt(id: UUID(), owner: owner, revision: revision, request: state.requestedRepair, started: Date())
                    state.attempt = target
                    state.error = nil
                    try store.save(state)
                    attemptID = target.id
                }
                let count = try await manager.reconcileSpotlight(using: index)
                let confirmation = try await store.acquire()
                let pending: Bool
                do {
                    defer { confirmation.release() }
                    var state = try store.load()
                    state.confirmedRevision = target.revision
                    state.confirmedRepair = target.request
                    state.confirmedOwner = owner
                    state.indexedCount = count
                    state.lastSuccessfulIndex = Date()
                    state.error = nil
                    state.attempt = nil
                    let current = try await manager.changeVersion().tasks
                    state.requestedRevision = current
                    try store.save(state)
                    pending = state.status(revision: current, owner: owner).pending
                    if !pending { try store.clearWarning() }
                    attemptID = nil
                }
                if !pending, generation == observedGeneration { break }
            }
        } catch {
            do {
                let lease = try await store.acquire()
                defer { lease.release() }
                var state = try store.load()
                if let attemptID {
                    if state.attempt?.id == attemptID {
                        state.attempt = nil
                        state.error = error.localizedDescription
                        try store.save(state)
                    }
                } else if operationLease != nil || state == admissionState {
                    state.error = error.localizedDescription
                    try store.save(state)
                }
            } catch {
                if operationLease != nil { await store.recordWarning(error.localizedDescription) }
                else { NSLog("tsk Spotlight admission failed: %@", error.localizedDescription) }
            }
        }
        running = nil
        if generation != observedGeneration { running = Task { await drain() } }
    }
}
#endif
