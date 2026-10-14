import Foundation
import Testing
import TskCore
import TskNative

@Test func annotationsSurviveNativeReopenAndConcurrentManagersWithoutLosingIdentity() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = TaskManager(replica: TaskChampionReplica(directory: directory), now: { Date(timeIntervalSince1970: 1792144800) })
    let original = try await manager.create(TaskDraft(description: "Preserve description", attributes: ["annotation_01": "Leading-zero note", "annotation_1": "Canonical note", "annotation_bad": "Malformed raw note", "opaque": "retain", "scheduled": "1792144800", "due": "1792231200"]))
    let other = TaskManager(replica: TaskChampionReplica(directory: directory), now: { Date(timeIntervalSince1970: 1792144800) })
    async let first = manager.addAnnotation(id: original.id, text: "First new note")
    async let second = other.addAnnotation(id: original.id, text: "Second new note")
    _ = try await (first, second)
    let edited = try await manager.editAnnotation(id: original.id, reference: "annotation_01", text: "  Edited\nleading-zero note  ")
    let reopened = TaskManager(replica: TaskChampionReplica(directory: directory))
    #expect(try await reopened.task(id: original.id) == edited)
    #expect(edited.id == original.id)
    #expect(edited.description == "Preserve description")
    #expect(edited.attributes["annotation_01"] == "  Edited\nleading-zero note  ")
    #expect(edited.attributes["annotation_1"] == "Canonical note")
    #expect(edited.attributes["annotation_bad"] == "Malformed raw note")
    #expect(Set(edited.annotations.filter { $0.reference.rawValue.hasPrefix("annotation_179214480") }.map(\.text)) == ["First new note", "Second new note"])
    #expect(edited.attributes["opaque"] == "retain")
    #expect(edited.attributes["scheduled"] == "1792144800")
    #expect(edited.attributes["due"] == "1792231200")
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"] != nil))
func taskwarriorReadsNativeAnnotationTimestampsAndItsNewNotePreservesNativeEdits() async throws {
    let binary = try #require(ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"])
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = TaskManager(replica: TaskChampionReplica(directory: directory), now: { Date(timeIntervalSince1970: 1792144800) })
    let original = try await manager.create(TaskDraft(description: "Annotation interoperability", attributes: ["annotation_1792144800": "Existing fixture", "opaque": "retain", "tag_home": ""]))
    _ = try await manager.addAnnotation(id: original.id, text: "\nNative multiline\nsecond line\n")
    let edited = try await manager.editAnnotation(id: original.id, reference: "annotation_1792144800", text: "Edited fixture")
    let config = directory.appendingPathComponent("taskrc")
    try "data.location=\(directory.path)\nuda.opaque.type=string\nconfirmation=no\n".write(to: config, atomically: true, encoding: .utf8)
    let output = try annotationTaskwarrior(binary: binary, config: config, arguments: ["export"])
    let records = try #require(JSONSerialization.jsonObject(with: output) as? [[String: Any]])
    let record = try #require(records.first)
    #expect((record["uuid"] as? String)?.lowercased() == edited.id.uuidString.lowercased())
    #expect(record["description"] as? String == "Annotation interoperability")
    #expect(record["opaque"] as? String == "retain")
    let annotations = try #require(record["annotations"] as? [[String: String]])
    #expect(annotations == [["entry": "20261016T100000Z", "description": "Edited fixture"], ["entry": "20261016T100001Z", "description": "\nNative multiline\nsecond line\n"]])
    _ = try annotationTaskwarrior(binary: binary, config: config, arguments: [original.id.uuidString.lowercased(), "annotate", "From Taskwarrior"])
    let reopened = TaskManager(replica: TaskChampionReplica(directory: directory))
    let task = try await reopened.task(id: original.id)
    #expect(task.annotations.count == 3)
    #expect(task.annotations.contains { $0.text == "From Taskwarrior" })
    #expect(task.attributes["annotation_1792144800"] == "Edited fixture")
    #expect(task.attributes["annotation_1792144801"] == "\nNative multiline\nsecond line\n")
    #expect(task.attributes["opaque"] == "retain")
}

private func annotationTaskwarrior(binary: String, config: URL, arguments: [String]) throws -> Data {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: binary)
    process.arguments = ["rc:\(config.path)", "rc.recurrence=off"] + arguments
    let output = Pipe()
    process.standardOutput = output
    let errors = Pipe()
    process.standardError = errors
    try process.run()
    let result = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let diagnostic = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    #expect(process.terminationStatus == 0, "Taskwarrior diagnostic: \(diagnostic)")
    return result
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"] != nil))
func taskwarriorRejectsNoncanonicalRawAnnotationTimestampWithoutChangingNativeEntries() async throws {
    let binary = try #require(ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"])
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = TaskManager(replica: TaskChampionReplica(directory: directory))
    let original = try await manager.create(TaskDraft(description: "Raw annotation identity", attributes: ["annotation_01": "Leading-zero note", "annotation_1": "Canonical note"]))
    let edited = try await manager.editAnnotation(id: original.id, reference: "annotation_01", text: "Changed leading-zero note")
    let config = directory.appendingPathComponent("taskrc")
    try "data.location=\(directory.path)\nconfirmation=no\n".write(to: config, atomically: true, encoding: .utf8)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: binary)
    process.arguments = ["rc:\(config.path)", "rc.recurrence=off", "export"]
    let output = Pipe()
    let errors = Pipe()
    process.standardOutput = output
    process.standardError = errors
    try process.run()
    _ = output.fileHandleForReading.readDataToEndOfFile()
    let diagnostic = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()
    #expect(process.terminationStatus == 2)
    #expect(diagnostic.contains("'01' is not a valid date"))
    #expect(try await manager.task(id: original.id) == edited)
    #expect(edited.attributes["annotation_01"] == "Changed leading-zero note")
    #expect(edited.attributes["annotation_1"] == "Canonical note")
    #expect(edited.annotations.count == 2)
}
