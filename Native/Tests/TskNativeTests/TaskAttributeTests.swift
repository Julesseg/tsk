import Foundation
import Testing
import TskCore
import TskNative

@Test func sharedFactoriesPersistByteExactAttributeDefinitionsWithoutTaskSynchronization() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = TaskChampionSession.makeManager(directory: directory)
    let second = try await TaskChampionSession.open(directory: directory)
    let configuration = try SyncConfiguration(serverURL: "https://tasks.example.test", clientID: UUID(), encryptionSecret: "isolated-secret")
    await first.configureSynchronization(configuration)
    _ = try await first.saveAttributeDefinition(name: "é", label: "Composed", type: .string)
    _ = try await second.saveAttributeDefinition(name: "e\u{301}", label: "Decomposed", type: .uuid)
    let reopened = TaskChampionSession.makeManager(directory: directory)
    let definitions = try await reopened.attributeDefinitions()
    #expect(definitions.count == 2)
    #expect(definitions.contains { $0.name == UTF8String("é") && $0.type == .string })
    #expect(definitions.contains { $0.name == UTF8String("e\u{301}") && $0.type == .uuid })
    try await first.deleteAttributeDefinition(name: "é")
    #expect(try await second.attributeDefinitions().map(\.name) == [UTF8String("e\u{301}")])
    #expect(try await first.tasks().isEmpty)
    #expect(await first.synchronizationStatus() == .ready)
    let permissions = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("attribute-definitions.json").path)[.posixPermissions] as? NSNumber
    #expect(permissions?.intValue == 0o600)
}

@Test func typedNativeValuesAndUnregisteredFieldsSurviveReopenAndDefinitionRemoval() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = TaskChampionSession.makeManager(directory: directory)
    for (name, type) in [("note", TaskAttributeType.string), ("score", .numeric), ("review", .date), ("effort", .duration), ("reference", .uuid)] { _ = try await manager.saveAttributeDefinition(name: name, type: type) }
    let original = try await manager.create(TaskDraft(description: "Typed native", attributes: ["opaque": "keep", "scheduled": "1792144800", "due": "1792231200"]))
    let saved = try await manager.updateUserAttributes(id: original.id, changes: ["note": "\nA note  ", "score": "-1.25", "review": "20261016T100000Z", "effort": "1.5h", "reference": "ABCDEF12"])
    let reopened = TaskChampionSession.makeManager(directory: directory)
    #expect(try await reopened.task(id: original.id) == saved)
    #expect(saved.attributes["review"] == "1792144800")
    #expect(saved.attributes["effort"] == "PT1H30M")
    #expect(saved.attributes["reference"] == "ABCDEF12")
    #expect(saved.attributes["opaque"] == "keep")
    try await reopened.deleteAttributeDefinition(name: "score")
    #expect(try await reopened.task(id: original.id) == saved)
    _ = try await reopened.update(id: original.id, changes: ["description": "Unrelated edit"])
    #expect(try await reopened.task(id: original.id).attributes["score"] == "-1.25")
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"] != nil))
func taskwarriorReadsAllFiveNativeAttributeTypesAndNativeReadsItsEdits() async throws {
    let binary = try #require(ProcessInfo.processInfo.environment["TSK_TASKWARRIOR_BINARY"])
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = TaskChampionSession.makeManager(directory: directory)
    let types: [(String, TaskAttributeType)] = [("note", .string), ("score", .numeric), ("review", .date), ("effort", .duration), ("reference", .uuid)]
    for (name, type) in types { _ = try await manager.saveAttributeDefinition(name: name, type: type) }
    let original = try await manager.create(TaskDraft(description: "Typed interchange", attributes: ["opaque": "keep"]))
    _ = try await manager.updateUserAttributes(id: original.id, changes: ["note": "Native note", "score": "-1.25", "review": "1792144800", "effort": "1.5h", "reference": "abcdef12"])
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

@Test func corruptAttributeMetadataFailsWithoutOverwritingTheOriginalFile() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("attribute-definitions.json")
    let original = Data("unreadable existing metadata".utf8)
    try original.write(to: file)
    let manager = TaskChampionSession.makeManager(directory: directory)
    await #expect(throws: (any Error).self) { try await manager.attributeDefinitions() }
    await #expect(throws: (any Error).self) { try await manager.saveAttributeDefinition(name: "score", type: .numeric) }
    #expect(try Data(contentsOf: file) == original)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["TSK_NATIVE_PROBE_BINARY"] != nil))
@MainActor func separateProcessesKeepBothAttributeDefinitionSnapshots() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = directory.appendingPathComponent("replica")
    let release = directory.appendingPathComponent("release")
    let firstReady = directory.appendingPathComponent("first-ready")
    let secondReady = directory.appendingPathComponent("second-ready")
    let firstOutput = directory.appendingPathComponent("first-output")
    let secondOutput = directory.appendingPathComponent("second-output")
    func launch(_ name: String, ready: URL, output: URL) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["TSK_NATIVE_PROBE_BINARY"]))
        process.arguments = ["save-attribute", storage.path, name, ready.path, release.path, output.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }
    let first = try launch("first", ready: firstReady, output: firstOutput)
    let second = try launch("second", ready: secondReady, output: secondOutput)
    defer {
        try? Data().write(to: release)
        for process in [first, second] { if process.isRunning { process.terminate() }; process.waitUntilExit() }
    }
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while !FileManager.default.fileExists(atPath: firstReady.path) && !FileManager.default.fileExists(atPath: secondReady.path) {
        guard ContinuousClock.now < deadline else { throw TaskManagementError.storage("No attribute writer reached its read") }
        try await Task.sleep(for: .milliseconds(10))
    }
    try await Task.sleep(for: .milliseconds(200))
    #expect(FileManager.default.fileExists(atPath: firstReady.path) != FileManager.default.fileExists(atPath: secondReady.path))
    try Data().write(to: release)
    while !FileManager.default.fileExists(atPath: firstOutput.path) || !FileManager.default.fileExists(atPath: secondOutput.path) || first.isRunning || second.isRunning {
        guard ContinuousClock.now < deadline else { throw TaskManagementError.storage("Attribute writer did not finish") }
        try await Task.sleep(for: .milliseconds(10))
    }
    let outputs = try [firstOutput, secondOutput].map { try #require(JSONSerialization.jsonObject(with: Data(contentsOf: $0)) as? [String: String]) }
    #expect(outputs.allSatisfy { $0["saved"] != nil })
    let reopened = TaskChampionSession.makeManager(directory: storage)
    #expect(Set(try await reopened.attributeDefinitions().map(\.name.rawValue)) == ["first", "second"])
    #expect(try await reopened.tasks().isEmpty)
}
