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
    let secondData = try Data(contentsOf: secondFile)
    let payload = try #require(JSONSerialization.jsonObject(with: secondData) as? [String: [[String: Any]]])
    #expect(payload["events"]?.map { $0["stage"] as? String } == ["second.pending", "second.pending"])
    #expect(payload["active"]?.isEmpty == true)
    #expect(try Data(contentsOf: firstFile) == original)
    recorder.finishRequest(second)
    recorder.event("after.completion", request: second, details: [:])
    #expect(try Data(contentsOf: secondFile) == secondData)
}
#endif
