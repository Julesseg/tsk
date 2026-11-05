#if DEBUG
import Foundation
import Testing
@testable import TskNative

@Test func shareDiagnosticsAreBoundToEachRequestAndRejectLateCompletions() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let recorder = TaskParticipantDiagnosticRecorder()
    let first = UUID(), second = UUID(), ordinary = UUID(), fixtureA = UUID(), fixtureB = UUID()
    recorder.beginRequest(first)
    recorder.enableShare(token: fixtureA, request: first, directory: directory)
    let old = recorder.begin("first.pending", request: first)
    recorder.beginRequest(ordinary)
    recorder.event("ordinary.private", request: ordinary, details: ["id": UUID().uuidString])
    recorder.end("first.pending", id: old)
    let firstFile = directory.appendingPathComponent("participant-fixture-share-\(fixtureA.uuidString)-\(ProcessInfo.processInfo.processIdentifier).json")
    TaskDiagnosticFileWriter.shared.flush()
    let original = try Data(contentsOf: firstFile)
    #expect(String(decoding: original, as: UTF8.self).contains("first.pending"))
    #expect(!String(decoding: original, as: UTF8.self).contains("ordinary.private"))
    recorder.beginRequest(second)
    recorder.enableShare(token: fixtureB, request: second, directory: directory)
    let current = recorder.begin("second.pending", request: second)
    recorder.event("old.callback", request: first, details: [:])
    recorder.end("first.pending", id: old)
    recorder.finishRequest(first)
    recorder.end("second.pending", id: current)
    let secondFile = directory.appendingPathComponent("participant-fixture-share-\(fixtureB.uuidString)-\(ProcessInfo.processInfo.processIdentifier).json")
    TaskDiagnosticFileWriter.shared.flush()
    let secondData = try Data(contentsOf: secondFile)
    let payload = try #require(JSONSerialization.jsonObject(with: secondData) as? [String: [[String: Any]]])
    #expect(payload["events"]?.map { $0["stage"] as? String } == ["second.pending", "second.pending"])
    #expect(payload["active"]?.isEmpty == true)
    #expect(try Data(contentsOf: firstFile) == original)
    recorder.finishRequest(second)
    recorder.event("after.completion", request: second, details: [:])
    TaskDiagnosticFileWriter.shared.flush()
    #expect(try Data(contentsOf: secondFile) == secondData)
}

@Test func aTestReplicaAloneDoesNotEnableExpensiveDiagnostics() {
    let token = UUID().uuidString
    #expect(TaskDiagnosticSettings.token(environment: ["TSK_TEST_REPLICA_NAME": token]) == nil)
    #expect(TaskDiagnosticSettings.token(environment: ["TSK_UI_DIAGNOSTICS": "1", "TSK_TEST_REPLICA_NAME": "invalid"]) == nil)
    #expect(TaskDiagnosticSettings.token(environment: ["TSK_UI_DIAGNOSTICS": "1", "TSK_TEST_REPLICA_NAME": token]) == token)
}

@Test func diagnosticWritesCoalescePerFileWithoutDroppingOtherParticipants() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let writer = TaskDiagnosticFileWriter(delay: .seconds(60))
    let first = directory.appendingPathComponent("first.json"), second = directory.appendingPathComponent("second.json")
    writer.submit(["phase": "begin"], to: first)
    writer.submit(["phase": "other"], to: second)
    writer.submit(["phase": "end"], to: first)
    #expect(!FileManager.default.fileExists(atPath: first.path))
    writer.flush()
    #expect(try JSONDecoder().decode([String: String].self, from: Data(contentsOf: first)) == ["phase": "end"])
    #expect(try JSONDecoder().decode([String: String].self, from: Data(contentsOf: second)) == ["phase": "other"])
}
#endif
