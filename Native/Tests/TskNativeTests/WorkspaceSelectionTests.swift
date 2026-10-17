import Foundation
import Testing
import TskCore
import TskNative

@Test func workspaceSelectionEditsAndCompletesOnePersistentNativeTask() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = TaskManager(replica: TaskChampionReplica(directory: directory))
    let first = try await manager.create(TaskDraft(description: "Keep pending", attributes: ["opaque": "first", "project": "Work"]))
    let second = try await manager.create(TaskDraft(description: "Select me", attributes: ["opaque": "second", "project": "Work", "scheduled": "1792144800", "due": "1792231200"]))
    let selected = try #require(manager.selectedTask(in: [first, second, first], from: first.id, moving: .next))
    _ = try await manager.update(id: selected, changes: ["description": "Edited with selected identity"])
    let completed = try await manager.complete(id: selected)
    let reopened = TaskManager(replica: TaskChampionReplica(directory: directory))
    #expect(try await reopened.task(id: selected) == completed)
    #expect(try await reopened.task(id: first.id).status == "pending")
    #expect(completed.attributes["opaque"] == "second")
    #expect(completed.attributes["scheduled"] == "1792144800")
    #expect(completed.attributes["due"] == "1792231200")
    if let binary = ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"] {
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
        let record = try #require(records.first { ($0["uuid"] as? String)?.lowercased() == selected.uuidString.lowercased() })
        #expect(record["status"] as? String == "completed")
        #expect(record["description"] as? String == "Edited with selected identity")
        #expect(record["opaque"] as? String == "second")
        #expect(records.count == 2)
    }
}
