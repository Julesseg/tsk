import Foundation
import XCTest

final class KeyboardCommandTests: XCTestCase {
    private let owner = "927C04C4-ADCC-415D-A1E6-DAEAE5087111"
    private let replica = "B9D12D0D-FDCF-47F9-B5CF-3B49A71A8A4B"

    private func session(_ name: TaskKeyboardSession.Case = .annotations) throws -> TaskKeyboardSession {
        try TaskKeyboardSession(owner: owner, caseName: name, replica: replica, runnerPID: 123, runnerBundleID: "com.julesseguin.tsk.uitests.xctrunner")
    }

    func testOnlyExpectedPhaseMayStartAndOnlyAcknowledgedPhaseMayAdvance() throws {
        let session = try session()
        XCTAssertThrowsError(try session.begin("secondNoteSave", now: 100))
        let first = try session.begin("secondNoteCommandN", now: 100)
        XCTAssertEqual(first.sequence, 0)
        XCTAssertEqual(first.expiresAt, 112)
        XCTAssertThrowsError(try session.begin("secondNoteSave", now: 101))
        try session.acknowledge(JSONEncoder().encode(TaskKeyboardAcknowledgement(request: first, state: "transportComplete")), now: 101)
        XCTAssertThrowsError(try session.begin("secondNoteCommandN", now: 101))
        XCTAssertEqual(try session.begin("secondNoteSave", now: 101).sequence, 1)
    }
}

extension KeyboardCommandTests {
    func testOwnerEnablementCannotSilentlyFallBackWhenMisconfigured() throws {
        XCTAssertFalse(try TaskKeyboardSession.usesHID(environment: [:]))
        XCTAssertFalse(try TaskKeyboardSession.usesHID(environment: ["CI": "true"]))
        XCTAssertTrue(try TaskKeyboardSession.usesHID(environment: ["TSK_TEST_HID_DRIVER": "1", "TSK_TEST_HID_RELAY_TOKEN": owner]))
        for environment in [["TSK_TEST_HID_DRIVER": "1"], ["TSK_TEST_HID_RELAY_TOKEN": owner], ["TSK_TEST_HID_DRIVER": "1", "TSK_TEST_HID_RELAY_TOKEN": "invalid"]] {
            XCTAssertThrowsError(try TaskKeyboardSession.usesHID(environment: environment))
        }
    }

    func testForeignPartialFailedExpiredAndReplayedAcknowledgementsCannotAdvance() throws {
        let session = try session()
        let request = try session.begin("secondNoteCommandN", now: 100)
        let foreign = try self.session().begin("secondNoteCommandN", now: 100)
        for acknowledgement in [TaskKeyboardAcknowledgement(request: foreign, state: "transportComplete"), TaskKeyboardAcknowledgement(request: request, state: "failed")] {
            XCTAssertThrowsError(try session.acknowledge(JSONEncoder().encode(acknowledgement), now: 101))
        }
        XCTAssertThrowsError(try session.acknowledge(Data("{\"state\":\"transportComplete\"}".utf8), now: 101))
        let valid = try JSONEncoder().encode(TaskKeyboardAcknowledgement(request: request, state: "transportComplete"))
        XCTAssertThrowsError(try session.acknowledge(valid, now: 112))
        try session.acknowledge(valid, now: 101)
        XCTAssertThrowsError(try session.acknowledge(valid, now: 101))
    }

    func testOnlyFixedCaseSequencesAreAcceptedAndAbortPreventsFurtherRequests() throws {
        for name in [TaskKeyboardSession.Case.annotations, .workspace] {
            let session = try session(name)
            for (index, phase) in name.phases.enumerated() {
                let request = try session.begin(phase, now: 100)
                XCTAssertEqual(request.sequence, index)
                try session.acknowledge(JSONEncoder().encode(TaskKeyboardAcknowledgement(request: request, state: "transportComplete")), now: 101)
            }
            XCTAssertThrowsError(try session.begin(name.phases[0], now: 102))
        }
        let session = try session()
        let request = try session.begin("secondNoteCommandN", now: 100)
        session.abort()
        XCTAssertThrowsError(try session.acknowledge(JSONEncoder().encode(TaskKeyboardAcknowledgement(request: request, state: "transportComplete")), now: 101))
        XCTAssertThrowsError(try session.begin("secondNoteCommandN", now: 101))
    }

    func testIndependentCaseRequiresActualReadyNativeBaseline() throws {
        let session = try session(.native)
        XCTAssertThrowsError(try session.begin("commandReturn", now: 100))
        let ready = TaskKeyboardRequest.NativeState(processID: 456, firstResponder: true, textLength: 1, textIsPlainN: true, commandNCount: 1, commandReturnCount: 0)
        let request = try session.begin("commandReturn", now: 100, nativeState: ready)
        XCTAssertEqual(request.nativeState, ready)
    }

    func testRunnerOwnedAtomicFilesRejectSymlinkAndOversizeAcknowledgements() throws {
        let documents = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: documents) }
        let request = try session().begin("secondNoteCommandN", now: 100)
        let files = try TaskKeyboardFiles(documents: documents, request: request)
        let raw = try files.writeRequest(request)
        XCTAssertEqual(try JSONDecoder().decode(TaskKeyboardRequest.self, from: raw), request)
        XCTAssertTrue(files.requestURL.path.contains(request.owner + "/" + request.attempt))
        XCTAssertThrowsError(try files.writeRequest(request))
        let acknowledgement = try JSONEncoder().encode(TaskKeyboardAcknowledgement(request: request, state: "transportComplete"))
        try acknowledgement.write(to: files.acknowledgementURL, options: .atomic)
        XCTAssertEqual(try files.readAcknowledgement(), acknowledgement)
        try Data(repeating: 0, count: 4097).write(to: files.acknowledgementURL, options: .atomic)
        XCTAssertThrowsError(try files.readAcknowledgement())
        try FileManager.default.removeItem(at: files.acknowledgementURL)
        try FileManager.default.createSymbolicLink(at: files.acknowledgementURL, withDestinationURL: files.requestURL)
        XCTAssertThrowsError(try files.readAcknowledgement())
        try files.abort(request)
        XCTAssertEqual(try JSONDecoder().decode(TaskKeyboardAcknowledgement.self, from: Data(contentsOf: files.abortURL)).state, "aborted")
        try FileManager.default.removeItem(at: documents.appendingPathComponent("TSKHID"))
        try FileManager.default.createSymbolicLink(at: documents.appendingPathComponent("TSKHID"), withDestinationURL: documents)
        XCTAssertThrowsError(try TaskKeyboardFiles(documents: documents, request: request))
    }
}
