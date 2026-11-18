#if DEBUG
import Foundation
import Testing
@testable import TskNative

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
