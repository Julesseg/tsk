import Foundation
import Testing
import TskCore
import TskNative

@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"] != nil))
func nativePlanningPersistsIndependentTaskwarriorDatesAndTodayActions() async throws {
    let binary = try #require(ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"])
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    let manager = TaskManager(replica: TaskChampionReplica(directory: directory), now: { Date(timeIntervalSince1970: 1791972000) }, calendar: calendar)
    let original = try await manager.create(TaskDraft(description: "Native planned task", attributes: ["scheduled": "1791928800", "due": "1792101600", "start": "1791928900", "opaque": "retain"]))
    #expect(try await manager.tasks(query: .today).map(\.id) == [original.id])
    let config = directory.appendingPathComponent("taskrc")
    try "data.location=\(directory.path)\nuda.opaque.type=string\nconfirmation=no\n".write(to: config, atomically: true, encoding: .utf8)
    let first = try exportedPlanningTask(binary: binary, config: config)
    #expect(first["scheduled"] as? String == "20261013T220000Z")
    #expect(first["due"] as? String == "20261015T220000Z")
    #expect(first["start"] as? String == "20261013T220140Z")
    _ = try await manager.update(id: original.id, changes: ["scheduled": "1792015200"])
    let reopened = TaskManager(replica: TaskChampionReplica(directory: directory), now: { Date(timeIntervalSince1970: 1791972000) }, calendar: calendar)
    let edited = try await reopened.task(id: original.id)
    #expect(edited.attributes["due"] == "1792101600")
    #expect(edited.attributes["start"] == "1791928900")
    #expect(edited.attributes["opaque"] == "retain")
    #expect(try await reopened.tasks(query: .today).isEmpty)
    _ = try await reopened.update(id: original.id, changes: ["due": "1791928800"])
    #expect(try await reopened.tasks(query: .today).map(\.id) == [original.id])
    let changed = try exportedPlanningTask(binary: binary, config: config)
    #expect(changed["scheduled"] as? String == "20261014T220000Z")
    #expect(changed["due"] as? String == "20261013T220000Z")
    #expect((changed["uuid"] as? String)?.lowercased() == original.id.uuidString.lowercased())
    _ = try await reopened.complete(id: original.id)
    #expect(try await reopened.tasks(query: .today).isEmpty)
    let completed = try exportedPlanningTask(binary: binary, config: config)
    #expect(completed["scheduled"] as? String == "20261014T220000Z")
    #expect(completed["due"] as? String == "20261013T220000Z")
    #expect(completed["status"] as? String == "completed")
    #expect(completed["opaque"] as? String == "retain")
}

private func exportedPlanningTask(binary: String, config: URL) throws -> [String: Any] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: binary)
    process.arguments = ["rc:\(config.path)", "rc.recurrence=off", "export"]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    let bytes = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
    let records = try #require(JSONSerialization.jsonObject(with: bytes) as? [[String: Any]])
    return try #require(records.first)
}
