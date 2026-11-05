import Foundation
import Testing
#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

@Test @MainActor func ownedSyncProxyCanTerminateAfterPublishingReadiness() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    let fixture = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/delayed-sync-proxy.py")
    process.arguments = [fixture.path, "http://127.0.0.1:1", directory.path, "FAIL"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    defer {
        if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
        try? FileManager.default.removeItem(at: directory)
    }
    try process.run()
    let readyDeadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !FileManager.default.fileExists(atPath: directory.appendingPathComponent("url").path), process.isRunning, ContinuousClock.now < readyDeadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    try #require(FileManager.default.fileExists(atPath: directory.appendingPathComponent("url").path))
    process.terminate()
    let exitDeadline = ContinuousClock.now.advanced(by: .seconds(5))
    while process.isRunning, ContinuousClock.now < exitDeadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(!process.isRunning)
}
