import Foundation
import Testing
import TskCore
import TskNative

@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"] != nil))
func nativeWaitPersistsAsPendingAndMatchesTaskwarriorVirtualWaitingTransitions() async throws {
    let binary = try #require(ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"])
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let reference = Date(timeIntervalSince1970: Double(Int(Date().timeIntervalSince1970)))
    let future = String(Int(reference.timeIntervalSince1970) + 3600)
    let past = String(Int(reference.timeIntervalSince1970) - 1)
    let manager = TaskManager(replica: TaskChampionReplica(directory: directory), now: { reference })
    let task = try await manager.create(TaskDraft(description: "Native waiting task", attributes: ["scheduled": "1791928800", "due": "1792015200", "wait": future, "opaque": "retain", "start": "1791928800"]))
    let reopened = TaskManager(replica: TaskChampionReplica(directory: directory), now: { reference })
    #expect(try await reopened.task(id: task.id).attributes["wait"] == future)
    #expect(try await reopened.availability(id: task.id).isWaiting)
    #expect(try await reopened.tasks(query: .today).map(\.id) == [task.id])
    let config = directory.appendingPathComponent("taskrc")
    try "data.location=\(directory.path)\nuda.opaque.type=string\nconfirmation=no\n".write(to: config, atomically: true, encoding: .utf8)
    let waiting = try waitingExport(binary: binary, config: config, filter: "status:waiting")
    #expect(waiting.count == 1)
    #expect((waiting.first?["uuid"] as? String)?.lowercased() == task.id.uuidString.lowercased())
    #expect(waiting.first?["status"] as? String == "pending")
    #expect(try waitingExport(binary: binary, config: config, filter: "status:pending").isEmpty)
    _ = try await reopened.update(id: task.id, changes: ["wait": past])
    #expect(try await reopened.availability(id: task.id).isAvailable)
    #expect(try waitingExport(binary: binary, config: config, filter: "status:waiting").isEmpty)
    #expect(try waitingExport(binary: binary, config: config, filter: "status:pending").count == 1)
    _ = try await reopened.update(id: task.id, changes: ["wait": future])
    #expect(try waitingExport(binary: binary, config: config, filter: "status:waiting").count == 1)
    _ = try await reopened.update(id: task.id, changes: ["wait": nil])
    let final = TaskManager(replica: TaskChampionReplica(directory: directory), now: { reference })
    let cleared = try await final.task(id: task.id)
    #expect(cleared.id == task.id)
    #expect(cleared.status == "pending")
    #expect(cleared.attributes["wait"] == nil)
    #expect(cleared.attributes["scheduled"] == "1791928800")
    #expect(cleared.attributes["due"] == "1792015200")
    #expect(cleared.attributes["start"] == "1791928800")
    #expect(cleared.attributes["opaque"] == "retain")
    #expect(try await final.availability(id: task.id).isAvailable)
    #expect(try await final.tasks(query: .today).map(\.id) == [task.id])
    #expect(try waitingExport(binary: binary, config: config, filter: "status:waiting").isEmpty)
    let pending = try waitingExport(binary: binary, config: config, filter: "status:pending")
    #expect(pending.count == 1)
    #expect(pending.first?["wait"] == nil)
}

private func waitingExport(binary: String, config: URL, filter: String) throws -> [[String: Any]] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: binary)
    process.arguments = ["rc:\(config.path)", "rc.recurrence=off", filter, "export"]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
    return try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
}
