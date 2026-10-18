import Foundation
import Testing
import TskCore
import TskNative

@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"] != nil))
func upcomingDatesReopenAsTwoEntriesForOneTaskwarriorIdentityAndCompleteTogether() async throws {
    let binary = try #require(ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"])
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    let manager = TaskManager(replica: TaskChampionReplica(directory: directory), now: { Date(timeIntervalSince1970: 1791972000) }, calendar: calendar)
    let task = try await manager.create(TaskDraft(description: "Upcoming persistent task", attributes: ["scheduled": "1792015200", "due": "1792101600", "opaque": "retain"]))
    let reopened = TaskManager(replica: TaskChampionReplica(directory: directory), now: { Date(timeIntervalSince1970: 1791972000) }, calendar: calendar)
    let groups = try await reopened.upcomingDays()
    #expect(groups.map(\.day) == [Date(timeIntervalSince1970: 1792015200), Date(timeIntervalSince1970: 1792101600)])
    #expect(groups.flatMap(\.entries).map(\.role) == [.planned, .deadline])
    #expect(Set(groups.flatMap(\.entries).map { $0.task.id }) == [task.id])
    #expect(try await reopened.tasks().count == 1)
    _ = try await reopened.update(id: task.id, changes: ["scheduled": "1792188000", "description": "Replanned persistent task"])
    let final = TaskManager(replica: TaskChampionReplica(directory: directory), now: { Date(timeIntervalSince1970: 1791972000) }, calendar: calendar)
    #expect(try await final.upcomingDays().flatMap(\.entries).map(\.role) == [.deadline, .planned])
    let config = directory.appendingPathComponent("taskrc")
    try "data.location=\(directory.path)\nuda.opaque.type=string\nconfirmation=no\n".write(to: config, atomically: true, encoding: .utf8)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: binary)
    process.arguments = ["rc:\(config.path)", "rc.recurrence=off", "export"]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
    let records = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    #expect(records.count == 1)
    let record = try #require(records.first)
    #expect((record["uuid"] as? String)?.lowercased() == task.id.uuidString.lowercased())
    #expect(record["scheduled"] as? String == "20261016T220000Z")
    #expect(record["due"] as? String == "20261015T220000Z")
    #expect(record["opaque"] as? String == "retain")
    _ = try await final.complete(id: groups[0].entries[0].task.id)
    let completed = TaskManager(replica: TaskChampionReplica(directory: directory), now: { Date(timeIntervalSince1970: 1791972000) }, calendar: calendar)
    #expect(try await completed.upcomingDays().isEmpty)
    #expect(try await completed.tasks().count == 1)
    #expect(try await completed.task(id: task.id).attributes["opaque"] == "retain")
}
