import Foundation
import Testing
import TskCore
import TskNative

@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_NATIVE_PROBE_BINARY"] != nil))
@MainActor func separateProcessesCannotCommitOpposingDependencyEdgesFromStaleValidatedSnapshots() async throws {
    for coordinated in [false, true] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = directory.appendingPathComponent("replica")
        let manager = TaskManager(replica: TaskChampionReplica(directory: storage))
        let first = try await manager.create(TaskDraft(description: "First", attributes: ["opaque": "preserved"]))
        let second = try await manager.create(TaskDraft(description: "Second"))
        let release = directory.appendingPathComponent("release")
        let aReady = directory.appendingPathComponent("a-ready")
        let bReady = directory.appendingPathComponent("b-ready")
        let aOutput = directory.appendingPathComponent("a-result")
        let bOutput = directory.appendingPathComponent("b-result")
        let a = try launchMutationProbe(storage: storage, source: first.id, prerequisite: second.id, ready: aReady, release: release, output: aOutput, coordinated: coordinated)
        let b = try launchMutationProbe(storage: storage, source: second.id, prerequisite: first.id, ready: bReady, release: release, output: bOutput, coordinated: coordinated)
        defer {
            try? Data().write(to: release)
            for process in [a, b] { if process.isRunning { process.terminate() }; process.waitUntilExit() }
        }
        if coordinated {
            try await waitForProbe { FileManager.default.fileExists(atPath: aReady.path) || FileManager.default.fileExists(atPath: bReady.path) }
            try await Task.sleep(for: .milliseconds(200))
            #expect(FileManager.default.fileExists(atPath: aReady.path) != FileManager.default.fileExists(atPath: bReady.path), "The other process must wait before reading its validation snapshot")
        } else {
            try await waitForProbe { FileManager.default.fileExists(atPath: aReady.path) && FileManager.default.fileExists(atPath: bReady.path) }
        }
        try Data().write(to: release)
        try await waitForProbe { FileManager.default.fileExists(atPath: aOutput.path) && FileManager.default.fileExists(atPath: bOutput.path) }
        try await waitForProbe { !a.isRunning && !b.isRunning }
        let outputs = try [aOutput, bOutput].map { try #require(JSONSerialization.jsonObject(with: Data(contentsOf: $0)) as? [String: String]) }
        #expect(outputs.filter { $0["saved"] != nil }.count == (coordinated ? 1 : 2))
        if coordinated { #expect(outputs.contains { $0["error"] == TaskManagementError.dependencyCycle.localizedDescription }) }
        let records = try await manager.tasks()
        #expect(records.filter { !$0.dependencyReferences.isEmpty }.count == (coordinated ? 1 : 2))
        #expect(try await manager.task(id: first.id).attributes["opaque"] == "preserved")
    }
}

private func launchMutationProbe(storage: URL, source: UUID, prerequisite: UUID, ready: URL, release: URL, output: URL, coordinated: Bool) throws -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["TSK_NATIVE_PROBE_BINARY"]))
    process.arguments = [storage.path, source.uuidString, prerequisite.uuidString, ready.path, release.path, output.path, coordinated ? "coordinated" : "uncoordinated"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    return process
}

@MainActor private func waitForProbe(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while !condition() {
        guard ContinuousClock.now < deadline else { throw TaskManagementError.storage("Mutation process probe timed out") }
        try await Task.sleep(for: .milliseconds(10))
    }
}
