import Foundation
import Testing
import TskCore
import TskNative

@Test func opaqueAttributeBytesSurviveOrdinaryEditsCompletionAndReopen() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = TaskChampionSession.makeManager(directory: directory)
    let raw: TaskAttributes = ["foreign_é": "composed", "foreign_e\u{301}": "decomposed", "note": "\nA note  ", "score": "invalid former typed value", "empty": ""]
    let original = try await manager.create(TaskDraft(description: "Opaque values", attributes: raw))
    _ = try await manager.update(id: original.id, changes: ["description": "Renamed", "project": "Work"])
    _ = try await manager.complete(id: original.id)
    let reopened = try await TaskChampionSession.open(directory: directory)
    let saved = try await reopened.task(id: original.id)
    for (key, value) in raw { #expect(saved.attributes[key]?.matchesBytes(value) == true) }
    #expect(saved.description == "Renamed" && saved.status == "completed")
}

@Test func retiredLocalDefinitionMetadataCannotBlockTaskUseOrBeOverwritten() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("attribute-definitions.json")
    let original = Data("unreadable retired metadata".utf8)
    try original.write(to: file)
    let manager = try await TaskChampionSession.open(directory: directory)
    let task = try await manager.create(TaskDraft(description: "Ordinary task"))
    #expect(try await manager.task(id: task.id) == task)
    #expect(try Data(contentsOf: file) == original)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"] != nil))
func taskwarriorReadsAllFiveNativeAttributeTypesAndNativeReadsItsEdits() async throws {
    let binary = try #require(ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"])
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = TaskChampionSession.makeManager(directory: directory)
    let types: [(String, TaskFilterAttributeType)] = [("note", .string), ("score", .numeric), ("review", .date), ("effort", .duration), ("reference", .uuid)]
    let original = try await manager.create(TaskDraft(description: "Typed interchange", attributes: ["opaque": "keep"]))
    _ = try await manager.update(id: original.id, changes: ["note": "Native note", "score": "-1.25", "review": "1792144800", "effort": "PT1H30M", "reference": "abcdef12"])
    let config = directory.appendingPathComponent("taskrc")
    let declarations = types.map { "uda.\($0.0).type=\($0.1.rawValue)" }.joined(separator: "\n")
    try "data.location=\(directory.path)\nconfirmation=no\nuda.opaque.type=string\n\(declarations)\n".write(to: config, atomically: true, encoding: .utf8)
    func run(_ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["rc:\(config.path)", "rc.recurrence=off"] + arguments
        var environment = ProcessInfo.processInfo.environment
        environment["TASKRC"] = config.path
        environment["TASKDATA"] = directory.path
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        return data
    }
    let rows = try #require(JSONSerialization.jsonObject(with: run(["export"])) as? [[String: Any]])
    let row = try #require(rows.first)
    #expect(row["note"] as? String == "Native note")
    #expect(row["score"] as? Double == -1.25)
    #expect(row["review"] as? String == "20261016T100000Z")
    #expect(row["effort"] as? String == "PT1H30M")
    #expect(row["reference"] as? String == "abcdef12")
    _ = try run([original.id.uuidString.lowercased(), "modify", "score:2.5", "review:20261017T100000Z", "effort:-30min", "reference:ABCDEF12"])
    let updated = try await manager.task(id: original.id)
    #expect(updated.attributes["score"] == "2.5")
    #expect(updated.attributes["review"] == "1792231200")
    #expect(updated.attributes["effort"] == "-PT30M")
    #expect(updated.attributes["reference"] == "ABCDEF12")
    #expect(updated.attributes["opaque"] == "keep")
}
