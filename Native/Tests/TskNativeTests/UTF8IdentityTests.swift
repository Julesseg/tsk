import Foundation
import Testing
import TskCore
import TskNative

@Test func nativeReopenKeepsDistinctUTF8FieldsAndTargetedTagRemoval() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = TaskManager(replica: TaskChampionReplica(directory: directory))
    let composed = "café"
    let decomposed = "cafe\u{301}"
    var draft = TaskDraft(description: "Unicode work")
    draft.attributes[composed] = "composed field"
    draft.attributes[decomposed] = "decomposed field"
    draft.project = composed
    try draft.addTag(composed)
    try draft.addTag(decomposed)
    let original = try await manager.create(draft)
    let reopened = TaskManager(replica: TaskChampionReplica(directory: directory))
    let loaded = try await reopened.task(id: original.id)
    #expect(loaded.attributes[composed] == "composed field")
    #expect(loaded.attributes[decomposed] == "decomposed field")
    #expect(loaded.tags.count == 2)
    _ = try await reopened.update(id: original.id, changes: ["description": "Unrelated edit"])
    _ = try await reopened.update(id: original.id, changes: ["tag_\(decomposed)": nil])
    let final = TaskManager(replica: TaskChampionReplica(directory: directory))
    let stored = try await final.task(id: original.id)
    #expect(stored.attributes[composed] == "composed field")
    #expect(stored.attributes[decomposed] == "decomposed field")
    #expect(stored.attributes["tag_\(composed)"] != nil)
    #expect(stored.attributes["tag_\(decomposed)"] == nil)
    #expect(stored.id == original.id)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"] != nil))
func taskwarriorExportRetainsUnicodeFieldsTagsAndExactProjectsAfterNativeEdits() async throws {
    let binary = try #require(ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"])
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = TaskManager(replica: TaskChampionReplica(directory: directory))
    let composed = "café"
    let decomposed = "cafe\u{301}"
    let original = try await manager.create(TaskDraft(description: "Unicode", attributes: [composed: "first", decomposed: "second", "project": composed, "tag_\(composed)": "", "tag_\(decomposed)": ""]))
    let other = try await manager.create(TaskDraft(description: "Other", attributes: ["project": decomposed]))
    let config = directory.appendingPathComponent("taskrc")
    try "data.location=\(directory.path)\nuda.\(composed).type=string\nuda.\(decomposed).type=string\nconfirmation=no\n".write(to: config, atomically: true, encoding: .utf8)
    func export() throws -> [TaskwarriorIdentityExport] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["rc:\(config.path)", "rc.recurrence=off", "export"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        return try decodeTaskwarriorIdentityExport(data)
    }
    let firstExport = try export()
    let before = try #require(firstExport.first { $0["uuid"] == original.id.uuidString.lowercased() })
    #expect(before[composed] == "first")
    #expect(before[decomposed] == "second")
    #expect(Set(before.tags.map { UTF8String($0) }) == [UTF8String(composed), UTF8String(decomposed)])
    _ = try await manager.update(id: original.id, changes: ["description": "Unrelated edit"])
    _ = try await manager.update(id: original.id, changes: ["tag_\(decomposed)": nil])
    let reopened = TaskManager(replica: TaskChampionReplica(directory: directory))
    #expect(try await reopened.tasks(project: .project(composed)).map(\.id) == [original.id])
    #expect(try await reopened.tasks(project: .project(decomposed)).map(\.id) == [other.id])
    let after = try #require(export().first { $0["uuid"] == original.id.uuidString.lowercased() })
    #expect(after[composed] == "first")
    #expect(after[decomposed] == "second")
    #expect(after["project"]?.matchesBytes(composed) == true)
    #expect(after.tags.map { UTF8String($0) } == [UTF8String(composed)])
}

@Test func taskwarriorExportObserverPreservesCanonicallyEquivalentKeys() throws {
    let data = Data(#"[{"café":"first","cafe\u0301":"second"}]"#.utf8)
    let row = try #require(decodeTaskwarriorIdentityExport(data).first)
    #expect(row["café"] == "first")
    #expect(row["cafe\u{301}"] == "second")
}

private struct TaskwarriorIdentityExport: Decodable {
    struct Field: Decodable { let key: String; let value: String }
    let fields: [Field]
    let tags: [String]
    subscript(_ key: String) -> String? { fields.first { $0.key.matchesBytes(key) }?.value }
}

private func decodeTaskwarriorIdentityExport(_ data: Data) throws -> [TaskwarriorIdentityExport] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    let fixture = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/taskwarrior-utf8-export.py")
    process.arguments = [fixture.path]
    let input = Pipe(), output = Pipe(), errors = Pipe()
    process.standardInput = input
    process.standardOutput = output
    process.standardError = errors
    try process.run()
    try input.fileHandleForWriting.write(contentsOf: data)
    try input.fileHandleForWriting.close()
    let projection = output.fileHandleForReading.readDataToEndOfFile()
    let diagnostics = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    try #require(process.terminationStatus == 0, Comment(rawValue: String(decoding: diagnostics, as: UTF8.self)))
    return try JSONDecoder().decode([TaskwarriorIdentityExport].self, from: projection)
}
