import Foundation
import Testing
import TskCore
import TskNative

@Test func organizationEditsAndProjectMembershipSurviveReopeningRealReplica() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = TaskManager(replica: TaskChampionReplica(directory: directory))
    var draft = TaskDraft(description: "Organized task", attributes: ["opaque": "retain", "annotation_1792015200": "Note"])
    draft.project = "Maison 📚"
    draft.priority = "H"
    try draft.addTag("Home")
    try draft.addTag("errands")
    let original = try await manager.create(draft)
    _ = try await manager.update(id: original.id, changes: ["project": "Work.sub", "priority": nil, "tag_errands": nil, "tag_next": ""])
    let reopened = TaskManager(replica: TaskChampionReplica(directory: directory))
    let revised = try await reopened.task(id: original.id)
    #expect(revised.id == original.id)
    #expect(revised.project == "Work.sub")
    #expect(revised.priority == "")
    #expect(revised.tags == ["Home", "next"])
    #expect(revised.attributes["tags"] == "Home,next")
    #expect(revised.attributes["opaque"] == "retain")
    #expect(revised.attributes["annotation_1792015200"] == "Note")
    #expect(try await reopened.tasks(project: .project("Maison 📚")).isEmpty)
    #expect(try await reopened.tasks(project: .project("Work.sub")) == [revised])
    #expect(try await reopened.projects() == ["Work.sub"])
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"] != nil))
func taskwarriorAgreesWithNativeTagsPrioritiesAndExactProjectViews() async throws {
    let binary = try #require(ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"])
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = TaskManager(replica: TaskChampionReplica(directory: directory))
    let original = try await manager.create(TaskDraft(description: "Work task", attributes: ["project": "Work", "priority": "H", "tag_home": "x", "tag_errands": "", "opaque": "retain"]))
    _ = try await manager.create(TaskDraft(description: "Nested task", attributes: ["project": "Work.sub"]))
    _ = try await manager.create(TaskDraft(description: "Different task", attributes: ["project": "Workplace"]))
    let config = directory.appendingPathComponent("taskrc")
    try "data.location=\(directory.path)\nuda.opaque.type=string\nconfirmation=no\n".write(to: config, atomically: true, encoding: .utf8)
    let exported = try exportTasks(binary: binary, config: config, filters: ["project.is:Work"])
    let native = try await manager.tasks(project: .project("Work"))
    #expect(Set(exported.compactMap { $0["uuid"] as? String }) == Set(native.map { $0.id.uuidString.lowercased() }))
    let record = try #require(exported.first)
    #expect(record["priority"] as? String == "H")
    #expect(Set(record["tags"] as? [String] ?? []) == ["home", "errands"])
    _ = try await manager.update(id: original.id, changes: ["project": "Household", "priority": "L", "tag_errands": nil, "tag_next": ""])
    let revisedExport = try exportTasks(binary: binary, config: config, filters: [original.id.uuidString.lowercased()])
    let revised = try #require(revisedExport.first)
    #expect(revised["project"] as? String == "Household")
    #expect(revised["priority"] as? String == "L")
    #expect(Set(revised["tags"] as? [String] ?? []) == ["home", "next"])
    #expect(revised["opaque"] as? String == "retain")
}

private func exportTasks(binary: String, config: URL, filters: [String]) throws -> [[String: Any]] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: binary)
    process.arguments = ["rc:\(config.path)", "rc.recurrence=off"] + filters + ["export"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try process.run()
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
    return try #require(JSONSerialization.jsonObject(with: output) as? [[String: Any]])
}
