import Foundation
import Testing
import TskCore
import TskNative

@Test func captureSurvivesClosingAndReopeningRealTaskChampionReplica() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = TaskManager(replica: TaskChampionReplica(directory: directory))
    let task = try await first.create(TaskDraft(description: "Buy milk", attributes: ["customOpaque": "retain exactly", "tag_errands": "", "annotation_1791975600": "From phone"]))
    let reopened = TaskManager(replica: TaskChampionReplica(directory: directory))
    #expect(try await reopened.task(id: task.id) == task)
    #expect(try await reopened.tasks().count == 1)
}

@Test func failedSaveReportsRealStorageFailureWithoutAcknowledgingTask() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data("not a directory".utf8).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    let manager = TaskManager(replica: TaskChampionReplica(directory: file))
    await #expect(throws: (any Error).self) {
        try await manager.create(TaskDraft(description: "Must not report saved"))
    }
}

@Test func independentClientsSeeEachOthersCommittedTasks() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = TaskManager(replica: TaskChampionReplica(directory: directory))
    let second = TaskManager(replica: TaskChampionReplica(directory: directory))
    let firstTask = try await first.create(TaskDraft(description: "First client"))
    let secondTask = try await second.create(TaskDraft(description: "Second client"))
    #expect(try await first.task(id: secondTask.id) == secondTask)
    #expect(try await second.task(id: firstTask.id) == firstTask)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"] != nil))
func taskwarriorReadsNativeCaptureAndItsEditRetainsOpaqueFields() async throws {
    let binary = try #require(ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"])
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let data = directory.appendingPathComponent("data")
    let manager = TaskManager(replica: TaskChampionReplica(directory: data))
    let task = try await manager.create(TaskDraft(description: "Native capture", attributes: ["customOpaque": "retain exactly", "tag_errands": "", "annotation_1792015200": "From native bridge"]))
    let config = directory.appendingPathComponent("taskrc")
    try "data.location=\(data.path)\nuda.customOpaque.type=string\nuda.customOpaque.label=Opaque\nconfirmation=no\n".write(to: config, atomically: true, encoding: .utf8)
    let export = try runTaskwarrior(binary: binary, config: config, arguments: ["export"])
    let records = try #require(JSONSerialization.jsonObject(with: export) as? [[String: Any]])
    let record = try #require(records.first)
    #expect((record["uuid"] as? String)?.lowercased() == task.id.uuidString.lowercased())
    #expect(record["customOpaque"] as? String == "retain exactly")
    #expect(record["tags"] as? [String] == ["errands"])
    _ = try runTaskwarrior(binary: binary, config: config, arguments: [task.id.uuidString.lowercased(), "modify", "description:Edited in Taskwarrior"])
    let updated = try await manager.task(id: task.id)
    #expect(updated.description == "Edited in Taskwarrior")
    #expect(updated.attributes["customOpaque"] == "retain exactly")
    #expect(updated.attributes["annotation_1792015200"] == "From native bridge")
}

private func runTaskwarrior(binary: String, config: URL, arguments: [String]) throws -> Data {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: binary)
    process.arguments = ["rc:\(config.path)", "rc.recurrence=off"] + arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
    return data
}

@Test func editsAndCompletionSurviveReopeningWithoutLosingAttributes() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = TaskManager(replica: TaskChampionReplica(directory: directory), now: { Date(timeIntervalSince1970: 1792015200) })
    let original = try await manager.create(TaskDraft(description: "Original", attributes: ["opaque": "retain", "annotation_1792015000": "Note", "tag_home": "", "start": "1792015100"]))
    _ = try await manager.update(id: original.id, changes: ["description": "Revised"])
    let reopened = TaskManager(replica: TaskChampionReplica(directory: directory), now: { Date(timeIntervalSince1970: 1792015260) })
    #expect(try await reopened.task(id: original.id).description == "Revised")
    let completed = try await reopened.complete(id: original.id)
    let final = TaskManager(replica: TaskChampionReplica(directory: directory))
    #expect(try await final.task(id: original.id) == completed)
    #expect(completed.attributes["status"] == "completed")
    #expect(completed.attributes["end"] == "1792015260")
    #expect(completed.attributes["modified"] == "1792015260")
    #expect(completed.attributes["start"] == nil)
    #expect(completed.attributes["opaque"] == "retain")
    #expect(completed.attributes["annotation_1792015000"] == "Note")
    #expect(completed.attributes["tag_home"] == "")
    #expect(try await final.tasks(query: .unfinished).isEmpty)
    #expect(try await final.tasks(query: .completed) == [completed])
}

@Test func removingOneRawAttributePreservesEveryOtherField() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = TaskManager(replica: TaskChampionReplica(directory: directory))
    let original = try await manager.create(TaskDraft(description: "Keep fields", attributes: ["removeMe": "value", "keepMe": "opaque"]))
    _ = try await manager.update(id: original.id, changes: ["removeMe": nil])
    let reopened = TaskManager(replica: TaskChampionReplica(directory: directory))
    let updated = try await reopened.task(id: original.id)
    #expect(updated.attributes["removeMe"] == nil)
    #expect(updated.attributes["keepMe"] == "opaque")
    #expect(updated.id == original.id)
    #expect(updated.description == "Keep fields")
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"] != nil))
func taskwarriorRecognizesNativeCompletionAndStoppedWork() async throws {
    let binary = try #require(ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"])
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = TaskManager(replica: TaskChampionReplica(directory: directory), now: { Date(timeIntervalSince1970: 1792015260) })
    let original = try await manager.create(TaskDraft(description: "Finish task", attributes: ["start": "1792015000", "opaque": "retain"]))
    _ = try await manager.update(id: original.id, changes: ["description": "Finished native edit"])
    _ = try await manager.complete(id: original.id)
    let config = directory.appendingPathComponent("taskrc")
    try "data.location=\(directory.path)\nuda.opaque.type=string\nconfirmation=no\n".write(to: config, atomically: true, encoding: .utf8)
    let output = try runTaskwarrior(binary: binary, config: config, arguments: ["export"])
    let records = try #require(JSONSerialization.jsonObject(with: output) as? [[String: Any]])
    let record = try #require(records.first)
    #expect(record["description"] as? String == "Finished native edit")
    #expect(record["status"] as? String == "completed")
    #expect(record["end"] as? String == "20261014T220100Z")
    #expect(record["opaque"] as? String == "retain")
    #expect(record["start"] == nil)
}
