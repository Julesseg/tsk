import Foundation
import Testing

@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_SYNC_TEST_URL"] != nil))
func separateProcessesCancelBlockedSynchronizationAndRecoverAfterOwnerDeathWithoutLosingLocalWrites() throws {
    let environment = ProcessInfo.processInfo.environment
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/multiprocess-admission.py")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = [fixture.path, try #require(environment["TSK_TASKCHAMPION_LIBRARY"]), try #require(environment["TSK_SYNC_TEST_URL"]), try #require(environment["TSK_SYNC_TEST_CLIENT_ID"]), try #require(environment["TSK_SYNC_TEST_SECRET"])]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0, Comment(rawValue: String(decoding: output, as: UTF8.self)))
}
