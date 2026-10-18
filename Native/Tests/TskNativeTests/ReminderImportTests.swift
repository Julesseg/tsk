import Foundation
import Testing
import TskCore
import TskNative

@Test func copiedRemindersPersistAsIndependentTasksThroughSharedFactoryAndTaskwarrior() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let manager = TaskChampionSession.makeManager(directory: directory, now: { Date(timeIntervalSince1970: 1792144800) }, calendar: calendar)
    let original = try await manager.create(TaskDraft(description: "Keep existing", attributes: ["opaque": "unchanged"]))
    let source = PersistentReminderSource()
    let result = try await manager.copyReminders(from: source, mappings: [ReminderListMapping(listID: "selected", project: "Imported.Work")])
    let imported = try #require(result.imported.first)
    #expect(result.imported.count == 1)
    #expect(imported.id != original.id)
    let reopened = TaskChampionSession.makeManager(directory: directory)
    #expect(try await reopened.task(id: imported.id) == imported)
    #expect(try await reopened.task(id: original.id) == original)
    #expect(imported.attributes["scheduled"] == "1792022400")
    #expect(imported.attributes["due"] == "1792143000")
    #expect(imported.annotations.map(\.text) == ["  Keep notes\nverbatim  ", "https://example.com/reminder"])
    #expect(imported.attributes.keys.allSatisfy { !$0.lowercased().contains("reminder") && !$0.lowercased().contains("source") })
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).allSatisfy { !$0.contains("import") && !$0.contains("reminder") })
    if let binary = ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"] {
        let config = directory.appendingPathComponent("taskrc")
        try "data.location=\(directory.path)\nconfirmation=no\n".write(to: config, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["rc:\(config.path)", "rc.recurrence=off", imported.id.uuidString.lowercased(), "export"]
        var environment = ProcessInfo.processInfo.environment
        environment["TASKRC"] = config.path; environment["TASKDATA"] = directory.path
        process.environment = environment
        let output = Pipe(); process.standardOutput = output
        let errors = Pipe(); process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "\(String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))")
        let record = try #require((JSONSerialization.jsonObject(with: data) as? [[String: Any]])?.first)
        #expect(record["scheduled"] as? String == "20261015T000000Z")
        #expect(record["due"] as? String == "20261016T093000Z")
        #expect(record["priority"] as? String == "M")
        #expect(record["project"] as? String == "Imported.Work")
        #expect((record["annotations"] as? [[String: String]])?.map { $0["description"] } == ["  Keep notes\nverbatim  ", "https://example.com/reminder"])
    }
}

private struct PersistentReminderSource: ReminderSource {
    func lists() async throws -> [ReminderList] { [ReminderList(id: "selected", title: "Work")] }
    func incompleteReminders(in listIDs: [String]) async throws -> [ReminderSnapshot] {
        [ReminderSnapshot(listID: "selected", title: "Native imported reminder", notes: "  Keep notes\nverbatim  ", url: "https://example.com/reminder", priority: 5,
                          start: DateComponents(year: 2026, month: 10, day: 15), due: DateComponents(year: 2026, month: 10, day: 16, hour: 9, minute: 30))]
    }
}
