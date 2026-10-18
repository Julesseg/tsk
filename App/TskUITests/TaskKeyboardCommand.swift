import Foundation

struct TaskKeyboardRequest: Codable, Equatable {
    let version: Int
    let owner: String
    let attempt: String
    let request: String
    let caseName: String
    let phase: String
    let sequence: Int
    let runnerPID: Int32
    let runnerBundleID: String
    let replica: String
    let expiresAt: Double
    let nativeState: NativeState?

    struct NativeState: Codable, Equatable {
        let processID: Int32
        let firstResponder: Bool
        let textLength: Int
        let textIsPlainN: Bool
        let commandNCount: Int
        let commandReturnCount: Int
    }
}

struct TaskKeyboardAcknowledgement: Codable {
    let request: TaskKeyboardRequest
    let state: String
}

struct TaskKeyboardCommandError: Error, CustomStringConvertible {
    let description: String
}

final class TaskKeyboardSession {
    enum Case: String {
        case native = "TaskAnnotationUITests/testIndependentNativeTextViewRecognizesPlainAndCommandKeys"
        case annotations = "TaskAnnotationUITests/testAddValidateEditAndReopenTimestampedAnnotations"
        case workspace = "iPadWorkspaceUITests/testInjectedKeyboardCaptureSelectionEditCompletionAndReopen"

        var phases: [String] {
            switch self {
            case .native: ["commandReturn"]
            case .annotations: ["secondNoteCommandN", "secondNoteSave", "editSelectAll", "editedNoteSave"]
            case .workspace: ["capture", "saveNew", "select", "edit", "saveEdit", "complete", "completedView"]
            }
        }
    }

    let owner: String
    let attempt: String
    let caseName: Case
    let replica: String
    let runnerPID: Int32
    let runnerBundleID: String
    private var sequence = 0
    private var pending: TaskKeyboardRequest?
    private var aborted = false

    init(owner: String, caseName: Case, replica: String, runnerPID: Int32, runnerBundleID: String, attempt: String = UUID().uuidString) throws {
        self.owner = try Self.identifier(owner)
        self.attempt = try Self.identifier(attempt)
        self.replica = try Self.identifier(replica)
        guard runnerPID > 0, runnerBundleID == "com.julesseguin.tsk.uitests.xctrunner" else {
            throw TaskKeyboardCommandError(description: "Invalid owned runner identity")
        }
        self.caseName = caseName
        self.runnerPID = runnerPID
        self.runnerBundleID = runnerBundleID
    }

    static func identifier(_ raw: String) throws -> String {
        guard let uuid = UUID(uuidString: raw), raw.lowercased() == uuid.uuidString.lowercased() else {
            throw TaskKeyboardCommandError(description: "Expected canonical UUID")
        }
        return uuid.uuidString.lowercased()
    }

    static func usesHID(environment: [String: String]) throws -> Bool {
        let enabled = environment["TSK_TEST_HID_DRIVER"]
        let owner = environment["TSK_TEST_HID_RELAY_TOKEN"]
        if enabled == nil && owner == nil { return false }
        guard enabled == "1", let owner else {
            throw TaskKeyboardCommandError(description: "Enabled HID driver requires its owned relay token")
        }
        _ = try identifier(owner)
        return true
    }

    func begin(_ phase: String, now: Double, nativeState: TaskKeyboardRequest.NativeState? = nil) throws -> TaskKeyboardRequest {
        guard !aborted, pending == nil, now.isFinite else { throw TaskKeyboardCommandError(description: "HID session is unavailable") }
        guard sequence < caseName.phases.count, phase == caseName.phases[sequence] else { throw TaskKeyboardCommandError(description: "Unexpected HID case phase") }
        if caseName == .native {
            guard let nativeState, nativeState.processID > 0, nativeState.firstResponder, nativeState.textLength == 1, nativeState.textIsPlainN, nativeState.commandNCount == 1, nativeState.commandReturnCount == 0 else {
                throw TaskKeyboardCommandError(description: "Native control baseline is not ready")
            }
        } else if nativeState != nil { throw TaskKeyboardCommandError(description: "Unexpected native control baseline") }
        let request = TaskKeyboardRequest(version: 1, owner: owner, attempt: attempt, request: UUID().uuidString.lowercased(), caseName: caseName.rawValue, phase: phase, sequence: sequence, runnerPID: runnerPID, runnerBundleID: runnerBundleID, replica: replica, expiresAt: now + 12, nativeState: nativeState)
        pending = request
        return request
    }

    func acknowledge(_ data: Data, now: Double) throws {
        guard let pending, !aborted, now.isFinite, now < pending.expiresAt, data.count <= 4096 else { throw TaskKeyboardCommandError(description: "Expired or unavailable HID request") }
        let acknowledgement = try JSONDecoder().decode(TaskKeyboardAcknowledgement.self, from: data)
        guard acknowledgement.request == pending, acknowledgement.state == "transportComplete" else { throw TaskKeyboardCommandError(description: "HID acknowledgement does not match the pending request") }
        self.pending = nil
        sequence += 1
    }

    func abort() { aborted = true }
}

struct TaskKeyboardFiles {
    let requestURL: URL
    let acknowledgementURL: URL
    let abortURL: URL

    init(documents: URL, request: TaskKeyboardRequest) throws {
        var directory = documents
        for component in ["TSKHID", try TaskKeyboardSession.identifier(request.owner), try TaskKeyboardSession.identifier(request.attempt)] {
            directory.appendPathComponent(component, isDirectory: true)
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            }
            let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw TaskKeyboardCommandError(description: "HID directory must be an owned regular directory") }
        }
        let identifier = try TaskKeyboardSession.identifier(request.request)
        requestURL = directory.appendingPathComponent(identifier + ".request.json")
        acknowledgementURL = directory.appendingPathComponent(identifier + ".ack.json")
        abortURL = directory.appendingPathComponent(identifier + ".abort.json")
    }

    func writeRequest(_ request: TaskKeyboardRequest) throws -> Data {
        let data = try JSONEncoder().encode(request)
        guard data.count <= 2048, !FileManager.default.fileExists(atPath: requestURL.path), !FileManager.default.fileExists(atPath: acknowledgementURL.path) else { throw TaskKeyboardCommandError(description: "HID request cannot overwrite an existing exchange") }
        try data.write(to: requestURL, options: .atomic)
        return data
    }

    func readAcknowledgement() throws -> Data {
        let attributes = try FileManager.default.attributesOfItem(atPath: acknowledgementURL.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular, let size = attributes[.size] as? NSNumber, size.intValue <= 4096 else { throw TaskKeyboardCommandError(description: "HID acknowledgement must be a bounded regular file") }
        let data = try Data(contentsOf: acknowledgementURL)
        guard data.count <= 4096 else { throw TaskKeyboardCommandError(description: "HID acknowledgement exceeds its byte budget") }
        return data
    }

    func abort(_ request: TaskKeyboardRequest) throws {
        try JSONEncoder().encode(TaskKeyboardAcknowledgement(request: request, state: "aborted")).write(to: abortURL, options: .atomic)
    }
}

#if canImport(UIKit) && canImport(XCTest)
import XCTest

@MainActor
final class TaskKeyboardCommand {
    private let session: TaskKeyboardSession?

    init(_ caseName: TaskKeyboardSession.Case, app: XCUIApplication) throws {
        let environment = ProcessInfo.processInfo.environment
        if try TaskKeyboardSession.usesHID(environment: environment) {
            guard environment["TSK_UI_ISOLATED_SIMULATOR"] == "1", let owner = environment["TSK_TEST_HID_RELAY_TOKEN"], let replica = app.launchEnvironment["TSK_TEST_REPLICA_NAME"], let runnerBundleID = Bundle.main.bundleIdentifier else { throw TaskKeyboardCommandError(description: "HID commands require the isolated owned runner and fixture") }
            session = try TaskKeyboardSession(owner: owner, caseName: caseName, replica: replica, runnerPID: ProcessInfo.processInfo.processIdentifier, runnerBundleID: runnerBundleID)
        } else { session = nil }
    }

    func perform(_ phase: String, nativeState: TaskKeyboardRequest.NativeState? = nil, fallback: () -> Void) throws {
        guard let session else { fallback(); return }
        let request = try session.begin(phase, now: Date().timeIntervalSince1970, nativeState: nativeState)
        var files: TaskKeyboardFiles?
        do {
            let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let exchange = try TaskKeyboardFiles(documents: documents, request: request)
            files = exchange
            let data = try exchange.writeRequest(request)
            Self.emit("TSK_KEYBOARD_COMMAND_REQUEST_V1 ", data: data)
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in FileManager.default.fileExists(atPath: exchange.acknowledgementURL.path) }, object: nil)
            guard XCTWaiter.wait(for: [ready], timeout: 12) == .completed else { throw TaskKeyboardCommandError(description: "HID transport acknowledgement exceeded 12 seconds") }
            try session.acknowledge(exchange.readAcknowledgement(), now: Date().timeIntervalSince1970)
        } catch {
            session.abort()
            let data = try JSONEncoder().encode(request)
            defer { Self.emit("TSK_KEYBOARD_COMMAND_ABORT_V1 ", data: data) }
            try files?.abort(request)
            throw error
        }
    }

    private static func emit(_ prefix: String, data: Data) {
        FileHandle.standardOutput.write(Data(prefix.utf8) + data + Data([10]))
    }
}
#endif
